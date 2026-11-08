class VirtualNumberSession {
  final String virtualPhone;
  final String tempId;

  VirtualNumberSession({required this.virtualPhone, required this.tempId});

  factory VirtualNumberSession.fromJson(Map<String, dynamic> json) {
    return VirtualNumberSession(
      virtualPhone: json['virtualPhone'],
      tempId: json['tempId'],
    );
  }
}
