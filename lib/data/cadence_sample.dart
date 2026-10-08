enum CadenceLinkState { simulated, connecting, connected, disconnected }

class CadenceSample {
  const CadenceSample({
    required this.at,
    required this.rpm,
    required this.link,
    this.detail,
  });

  final DateTime at;
  final double rpm;
  final CadenceLinkState link;
  final String? detail;
}
