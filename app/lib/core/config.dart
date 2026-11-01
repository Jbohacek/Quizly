/// Build-time configuration.
///
/// `--dart-define=API_BASE_URL=https://quizly.jbohacek.cz` (CLAUDE.md §11).
/// For a local API use e.g. `http://10.0.2.2:5278` (emulator) or the PC's LAN address (phone).
const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'https://quizly.jbohacek.cz');
