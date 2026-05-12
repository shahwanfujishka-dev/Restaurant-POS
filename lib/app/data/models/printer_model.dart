enum PrinterType { bluetooth, wifi }

class PrinterModel {
  String name;
  final String address;
  final String type; // 'bluetooth' or 'wifi'
  final dynamic device; // Original device object
  final bool isLikelyPrinter;

  PrinterModel({
    required this.name,
    required this.address,
    required this.type,
    this.device,
    this.isLikelyPrinter = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is PrinterModel &&
              runtimeType == other.runtimeType &&
              address == other.address;

  @override
  int get hashCode => address.hashCode;
}
