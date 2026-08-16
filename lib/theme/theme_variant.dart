/// How the app is themed.
///
///  * [light] — always light mode with the brand (Pocket red) palette.
///  * [dark] — always dark mode with the brand palette.
///  * [dynamic] — follows the system: the platform's Material You palette in
///    the system's light/dark mode (falls back to the brand palette on
///    devices without dynamic color support).
enum ThemeVariant {
  light('Light'),
  dark('Dark'),
  dynamic('Dynamic');

  const ThemeVariant(this.label);

  final String label;
}
