from __future__ import annotations


_PREP_GROUP_DEFINITIONS = {
    "zapiekanki": {
        "label": "Zapiekanki",
        "keywords": ("zapiek",),
    },
    "frytki": {
        "label": "Frytki",
        "keywords": ("frytk", "fries"),
    },
    "lody": {
        "label": "Lody",
        "keywords": ("lod", "ice cream", "gelato"),
    },
    "udka": {
        "label": "Udka",
        "keywords": ("udk", "udko", "kurcz", "chicken"),
    },
}


def infer_prep_group_key(
    position_type: str | None,
    name: str | None,
) -> str | None:
    haystack = " ".join(
        part.strip().lower()
        for part in (position_type or "", name or "")
        if part and part.strip()
    )
    if not haystack:
        return None

    for group_key, definition in _PREP_GROUP_DEFINITIONS.items():
        if any(keyword in haystack for keyword in definition["keywords"]):
            return group_key

    return None


def prep_group_label(group_key: str | None) -> str | None:
    if group_key is None:
        return None
    definition = _PREP_GROUP_DEFINITIONS.get(group_key)
    if definition is None:
        return None
    return definition["label"]
