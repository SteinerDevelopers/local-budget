import 'package:flutter/material.dart';

/// The 32-icon grid the Manage add/edit sheet shows (spec §2.4, 4×8) and the
/// key → [IconData] lookup the whole app uses. Keys are the `Icons.*`
/// constant names so a stored key is self-describing; the db only ever
/// stores these strings.
abstract final class ManageIcons {
  static const Map<String, IconData> grid = {
    'restaurant_outlined': Icons.restaurant_outlined,
    'local_cafe': Icons.local_cafe,
    'local_grocery_store': Icons.local_grocery_store,
    'local_dining': Icons.local_dining,
    'directions_bus_outlined': Icons.directions_bus_outlined,
    'directions_car': Icons.directions_car,
    'directions_bike': Icons.directions_bike,
    'directions_walk': Icons.directions_walk,
    'flight': Icons.flight,
    'train': Icons.train,
    'local_gas_station': Icons.local_gas_station,
    'bolt_outlined': Icons.bolt_outlined,
    'water_drop': Icons.water_drop,
    'home_outlined': Icons.home_outlined,
    'apartment': Icons.apartment,
    'business_center': Icons.business_center,
    'work_outline': Icons.work_outline,
    'school': Icons.school,
    'laptop': Icons.laptop,
    'phone_iphone': Icons.phone_iphone,
    'monitor_heart_outlined': Icons.monitor_heart_outlined,
    'local_hospital': Icons.local_hospital,
    'fitness_center': Icons.fitness_center,
    'child_care': Icons.child_care,
    'pets': Icons.pets,
    'park': Icons.park,
    'local_florist': Icons.local_florist,
    'shopping_bag': Icons.shopping_bag,
    'local_mall': Icons.local_mall,
    'movie_outlined': Icons.movie_outlined,
    'sports_esports': Icons.sports_esports,
    'savings': Icons.savings,
  };

  /// Resolution order: stored key (§2.4) → legacy by-name fallback → generic.
  static IconData of(String? key, String? categoryName) =>
      grid[key] ?? _byName[categoryName] ?? Icons.label_outline;

  /// Pre-#18 rows have no stored key; keep the #17 mapping so they render
  /// exactly as before.
  static const Map<String, IconData> _byName = {
    'Food': Icons.restaurant_outlined,
    'Housing': Icons.home_outlined,
    'Transport': Icons.directions_bus_outlined,
    'Utilities': Icons.bolt_outlined,
    'Fun': Icons.movie_outlined,
    'Health': Icons.monitor_heart_outlined,
    'Salary': Icons.payments_outlined,
    'Other income': Icons.trending_up,
  };
}
