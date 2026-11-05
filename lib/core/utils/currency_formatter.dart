import 'package:intl/intl.dart';

abstract final class CurrencyFormatter {
  // en_US fixes "." as decimal separator and "," for thousands regardless of
  // the device locale, e.g. Q1,000.00.
  static final NumberFormat _quetzal = NumberFormat.currency(
    locale: 'en_US',
    name: 'GTQ',
    symbol: 'Q',
    decimalDigits: 2,
  );

  static String formatGtq(num amount) => _quetzal.format(amount);
}
