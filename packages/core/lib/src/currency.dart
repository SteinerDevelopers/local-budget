// Steiner Budget — local-first budgeting, https://steinerdevelopers.dev
// Copyright (C) 2026 Steiner Developers, L.L.C.
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

/// ISO-4217 currency metadata needed by [Money].
///
/// Decision 6: the base currency is set once per device; every stored amount
/// carries its own currency code, so multi-currency amounts coexist freely.
class Currency {
  const Currency(this.code, this.symbol, this.minorUnits, this.displayName);

  /// ISO-4217 code, e.g. `USD`.
  final String code;

  /// Display symbol; only ever used for rendering, never parsing.
  final String symbol;

  /// Digits after the decimal point (JPY/KRW/VND: 0, BHD/KWD: 3, most: 2).
  final int minorUnits;

  final String displayName;

  static const Map<String, Currency> known = {
    'USD': Currency('USD', r'$', 2, 'US Dollar'),
    'EUR': Currency('EUR', '€', 2, 'Euro'),
    'GBP': Currency('GBP', '£', 2, 'British Pound'),
    'CAD': Currency('CAD', r'CA$', 2, 'Canadian Dollar'),
    'AUD': Currency('AUD', r'A$', 2, 'Australian Dollar'),
    'JPY': Currency('JPY', '¥', 0, 'Japanese Yen'),
    'KRW': Currency('KRW', '₩', 0, 'South Korean Won'),
    'CNY': Currency('CNY', '¥', 2, 'Chinese Yuan'),
    'CHF': Currency('CHF', 'CHF', 2, 'Swiss Franc'),
    'SEK': Currency('SEK', 'kr', 2, 'Swedish Krona'),
    'NOK': Currency('NOK', 'kr', 2, 'Norwegian Krone'),
    'DKK': Currency('DKK', 'kr', 2, 'Danish Krone'),
    'PLN': Currency('PLN', 'zł', 2, 'Polish Zloty'),
    'CZK': Currency('CZK', 'Kč', 2, 'Czech Koruna'),
    'HUF': Currency('HUF', 'Ft', 2, 'Hungarian Forint'),
    'INR': Currency('INR', '₹', 2, 'Indian Rupee'),
    'BRL': Currency('BRL', r'R$', 2, 'Brazilian Real'),
    'MXN': Currency('MXN', r'Mex$', 2, 'Mexican Peso'),
    'NZD': Currency('NZD', r'NZ$', 2, 'New Zealand Dollar'),
    'SGD': Currency('SGD', r'S$', 2, 'Singapore Dollar'),
    'ISK': Currency('ISK', 'kr', 0, 'Icelandic Krona'),
    'BHD': Currency('BHD', '.BD', 3, 'Bahraini Dinar'),
    'KWD': Currency('KWD', 'KD', 3, 'Kuwaiti Dinar'),
  };

  static Currency? find(String code) => known[code.toUpperCase()];

  /// Falls back to a 2-minor-unit currency with the raw code as symbol, so an
  /// unknown store's currency never blocks manual entry.
  static Currency resolve(String code) =>
      find(code.toUpperCase()) ??
      Currency(code.toUpperCase(), code.toUpperCase(), 2, code.toUpperCase());

  int get pow10 => switch (minorUnits) {
        0 => 1,
        1 => 10,
        2 => 100,
        3 => 1000,
        _ => 100,
      };
}
