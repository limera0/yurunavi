class PickFeature {
  final String layerId;
  final double screenDist;
  final Map<String, dynamic> props;

  const PickFeature({
    required this.layerId,
    required this.screenDist,
    required this.props,
  });
}

class PoiFeaturePicker {
  static const _rank = {
    'poi-level-1': 0,
    'poi-level-2': 1,
    'poi-level-3': 2,
    'poi-railway': 3,
    'place-city': 4,
    'place-town': 5,
    'place-village': 6,
    'place-other': 7,
  };

  static PickFeature? pick(List<PickFeature> candidates) {
    if (candidates.isEmpty) return null;
    return candidates.reduce((a, b) {
      final ra = _rank[a.layerId] ?? 999;
      final rb = _rank[b.layerId] ?? 999;
      if (ra != rb) return ra < rb ? a : b;
      return a.screenDist <= b.screenDist ? a : b;
    });
  }
}
