from __future__ import annotations

import base64
import re
import runpy
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "bin" / "mdview"
MDVIEW = runpy.run_path(str(SCRIPT_PATH), run_name="mdview_test_module")
render_markdown = MDVIEW["render_markdown"]
render_document_page = MDVIEW["render_document_page"]
APP = MDVIEW["APP"]
VIEW_TEMPLATE = MDVIEW["VIEW_TEMPLATE"]


def copy_payload(content_html: str, control_class: str) -> str:
    match = re.search(
        rf'class="[^"]*{re.escape(control_class)}[^"]*"[^>]*data-copy-b64="([^"]+)"',
        content_html,
    )
    if match is None:
        raise AssertionError(f"Copy control {control_class!r} was not rendered")
    return base64.b64decode(match.group(1)).decode("utf-8")


class MarkdownRenderingTests(unittest.TestCase):
    def test_linked_inline_code_does_not_create_nested_copy_target(self) -> None:
        page = render_markdown(
            "# Lesson with `CoroutineScope`\n\n"
            "- [`CoroutineScope` API](https://example.com/api)\n"
        )

        self.assertNotIn('href="#copy"', page.content_html)
        self.assertNotIn("copy-link-inline", page.content_html)
        self.assertIn(
            '<a href="https://example.com/api" rel="noreferrer" target="_blank">'
            "<code>CoroutineScope</code> API</a>",
            page.content_html,
        )
        self.assertEqual(page.content_html.count("data-copy-b64="), 1)

    def test_table_copy_preserves_exact_markdown_source(self) -> None:
        table = (
            "| Name | `Value` |\n"
            "| :--- | ---: |\n"
            "| a\\|b | Привет |\n"
        )
        page = render_markdown(f"Before\n\n{table}\nAfter\n")

        self.assertEqual(copy_payload(page.content_html, "copy-control-table"), table)
        self.assertIn("Copy table", page.content_html)
        self.assertIn('<div class="table-scroll"><table>', page.content_html)

    def test_code_controls_keep_raw_payloads(self) -> None:
        page = render_markdown(
            "Text `значение`\n\n"
            "```kotlin\nprintln(\"ok\")\n```\n"
        )

        self.assertEqual(copy_payload(page.content_html, "copy-inline"), "значение")
        self.assertEqual(
            copy_payload(page.content_html, "copy-control-block"),
            'println("ok")\n',
        )
        self.assertIn("Copy code", page.content_html)

    def test_code_panel_renders_chatgpt_style_language_header(self) -> None:
        page = render_markdown(
            "```kotlin\nprivate data class Example(val value: String)\n```\n"
        )

        self.assertIn(
            '<div class="code-block-wrap"><div class="code-block-header">',
            page.content_html,
        )
        self.assertIn(
            '<span class="code-language-label">Kotlin</span>',
            page.content_html,
        )
        self.assertEqual(page.content_html.count('class="code-block-icon"'), 1)
        self.assertEqual(page.content_html.count('class="copy-icon"'), 1)
        self.assertIn('aria-label="Copy code"', page.content_html)
        self.assertIn('<span class="kd">private</span>', page.content_html)

    def test_untagged_code_block_uses_neutral_code_label(self) -> None:
        code = "val message = \"Привет\"\n"
        page = render_markdown(f"    {code}")

        self.assertIn(
            '<span class="code-language-label">Code</span>',
            page.content_html,
        )
        self.assertEqual(copy_payload(page.content_html, "copy-control-block"), code)

    def test_empty_toc_is_hidden_and_heading_toc_is_visible(self) -> None:
        empty_page = render_markdown("Plain text only.\n")
        heading_page = render_markdown("# Heading\n")

        self.assertFalse(empty_page.has_toc)
        self.assertTrue(heading_page.has_toc)

        with APP.app_context():
            empty_html = render_document_page(
                page=empty_page,
                source_name="plain.md",
                source_description="plain.md",
                source_path=None,
                upload_mode=True,
            )
            heading_html = render_document_page(
                page=heading_page,
                source_name="heading.md",
                source_description="heading.md",
                source_path=None,
                upload_mode=True,
            )

        self.assertIn('id="toc-card" class="toc-card" hidden', empty_html)
        self.assertIn('id="toc-card" class="toc-card">', heading_html)

    def test_fragment_exposes_toc_state_for_live_reload(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "document.md"
            client = APP.test_client()

            path.write_text("No headings.\n", encoding="utf-8")
            response = client.get("/fragment", query_string={"path": str(path)})
            self.assertEqual(response.status_code, 200)
            self.assertFalse(response.get_json()["has_toc"])

            path.write_text("# Added heading\n", encoding="utf-8")
            response = client.get("/fragment", query_string={"path": str(path)})
            self.assertEqual(response.status_code, 200)
            self.assertTrue(response.get_json()["has_toc"])

        self.assertIn("tocCard.hidden = !fragment.has_toc;", VIEW_TEMPLATE)
        self.assertIn("keepTocLinkVisible(link);", VIEW_TEMPLATE)
        self.assertNotIn("link.scrollIntoView", VIEW_TEMPLATE)

    def test_toc_is_nested_and_duplicate_anchors_stay_unique(self) -> None:
        page = render_markdown(
            "# Root\n\n"
            "### Skipped level\n\n"
            "#### Deep\n\n"
            "## Repeated\n\n"
            "## Repeated\n\n"
            "# Another root\n"
        )

        self.assertIn('id="toc-children-root"', page.toc_html)
        self.assertIn('id="toc-children-skipped-level"', page.toc_html)
        self.assertIn('href="#repeated"', page.toc_html)
        self.assertIn('href="#repeated-1"', page.toc_html)
        self.assertIn('aria-expanded="false"', page.toc_html)
        self.assertIn('class="toc-children" hidden', page.toc_html)


if __name__ == "__main__":
    unittest.main()
