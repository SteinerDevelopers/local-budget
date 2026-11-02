import 'package:core/core.dart' show TransactionSource;
import 'package:drift/drift.dart';

/// Stores [TransactionSource.wireName] — stable strings, safe across enum
/// reordering and app upgrades.
class TransactionSourceConverter
    extends TypeConverter<TransactionSource, String> {
  const TransactionSourceConverter();

  @override
  TransactionSource fromSql(String fromDb) =>
      TransactionSource.fromWire(fromDb);

  @override
  String toSql(TransactionSource value) => value.wireName;
}
