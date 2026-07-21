import json

NEW_WIDTHS = {
    "highway-primary-casing": [
        "case",
        ["any", ["==", ["get", "oneway"], 1], ["==", ["get", "oneway"], -1]],
        ["interpolate", ["exponential", 1.3], ["zoom"],
            13, 2, 15, 6, 16, 10, 17, 16, 18, 24, 20, 40],
        ["interpolate", ["exponential", 1.2], ["zoom"],
            7, 0, 8, 0.6, 9, 1.5, 20, 22]
    ],
    "highway-primary": [
        "case",
        ["any", ["==", ["get", "oneway"], 1], ["==", ["get", "oneway"], -1]],
        ["interpolate", ["exponential", 1.3], ["zoom"],
            13, 1, 15, 4, 16, 7, 17, 11, 18, 16, 20, 28],
        ["interpolate", ["exponential", 1.2], ["zoom"],
            8.5, 0, 9, 0.5, 20, 18]
    ],
    "highway-secondary-tertiary-casing": [
        "case",
        ["any", ["==", ["get", "oneway"], 1], ["==", ["get", "oneway"], -1]],
        ["interpolate", ["exponential", 1.3], ["zoom"],
            13, 1.5, 15, 5, 16, 8, 17, 13, 18, 20, 20, 34],
        ["interpolate", ["exponential", 1.2], ["zoom"],
            8, 1.5, 20, 17]
    ],
    "highway-secondary-tertiary": [
        "case",
        ["any", ["==", ["get", "oneway"], 1], ["==", ["get", "oneway"], -1]],
        ["interpolate", ["exponential", 1.3], ["zoom"],
            13, 0.8, 15, 3, 16, 5.5, 17, 9, 18, 14, 20, 24],
        ["interpolate", ["exponential", 1.2], ["zoom"],
            6.5, 0, 8, 0.5, 20, 13]
    ],
}

for path in ["yurunavi_osm_bright.json", "assets/images/osm_liberty_yurunavi.json"]:
    with open(path, "r", encoding="utf-8") as f:
        style = json.load(f)

    patched = []
    for layer in style["layers"]:
        if layer["id"] in NEW_WIDTHS:
            layer["paint"]["line-width"] = NEW_WIDTHS[layer["id"]]
            patched.append(layer["id"])

    with open(path, "w", encoding="utf-8") as f:
        json.dump(style, f, ensure_ascii=False, indent=2)

    print(path, "-> patched:", patched)
