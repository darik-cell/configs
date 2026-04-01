def draw_title(data):
    title = " ".join(str(data.get("title") or "").split())
    index = int(data.get("index", 0) or 0)

    if not title:
        title = "tab"

    if 1 <= index <= 9:
        return f"{index} {title}"

    return title
