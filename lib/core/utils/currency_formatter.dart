import 'package:intl/intl.dart';

abstract final class CurrencyFormatter {
  static final NumberFormat _quetzal = NumberFormat.currency(
    locale: 'es_GT',
    name: 'GTQ',
    symbol: 'Q',
  );

  static String formatGtq(num amount) => _quetzal.format(amount);
}
