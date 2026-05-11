/// Formate un montant en euros sans arrondi trompeur.
/// Règle : si le montant est entier → "3 €", sinon → "3.80 €"
/// Exemples :
///   3.8  → "3.80"   (pas "4" !)
///   4.0  → "4"
///   10.5 → "10.50"
///   2.0  → "2"
String fmtEuros(double v) {
  if (v == v.truncateToDouble()) {
    return v.toStringAsFixed(0);
  }
  // Arrondir à 2 décimales proprement (évite les 3.7999999...)
  final s = (v * 100).round() / 100;
  return s.toStringAsFixed(2);
}
