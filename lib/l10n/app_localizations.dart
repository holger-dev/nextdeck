import 'package:flutter/widgets.dart';

class L10n {
  final Locale locale;
  const L10n(this.locale);

  static const supported = [Locale('de'), Locale('en'), Locale('es')];

  static L10n of(BuildContext context) {
    return Localizations.of<L10n>(context, L10n) ?? L10n(const Locale('en'));
  }

  static const LocalizationsDelegate<L10n> delegate = _L10nDelegate();

  String get _lang => locale.languageCode.toLowerCase();
  bool get _isDe => _lang == 'de';
  bool get _isEs => _lang == 'es';

  String get search => _isDe ? 'Suchen' : _isEs ? 'Buscar' : 'Search';
  String searchInBoard(String title) => _isDe
      ? 'Suchen im Board $title'
      : _isEs
          ? 'Buscar en el tablero $title'
          : 'Search in board $title';
  String get searchScopeCurrent => _isDe ? 'Aktuelles Board' : _isEs ? 'Tablero actual' : 'Current board';
  String get searchScopeAll => _isDe ? 'Alle Boards' : _isEs ? 'Todos los tableros' : 'All boards';

  String get newCard => _isDe ? 'Neue Karte' : _isEs ? 'Nueva tarjeta' : 'New card';
  String get title => _isDe ? 'Titel' : _isEs ? 'Título' : 'Title';
  String get create => _isDe ? 'Erstellen' : _isEs ? 'Crear' : 'Create';
  String get cancel => _isDe ? 'Abbrechen' : _isEs ? 'Cancelar' : 'Cancel';
  String get ok => 'OK';
  String get selectColumn => _isDe ? 'Liste auswählen' : _isEs ? 'Seleccionar columna' : 'Select column';
  String get pleaseSelectBoard => _isDe
      ? 'Bitte Board in den Einstellungen auswählen.'
      : _isEs
          ? 'Seleccione un tablero en ajustes.'
          : 'Please select a board in settings.';
  String get move => _isDe ? 'Verschieben' : _isEs ? 'Mover' : 'Move';
  String get labels => _isDe ? 'Labels' : _isEs ? 'Etiquetas' : 'Labels';
  String get newLabel => _isDe ? 'Neues Label' : _isEs ? 'Nueva etiqueta' : 'New label';
  String get addNewLabel => _isDe ? 'Neues Label hinzufügen' : _isEs ? 'Añadir nueva etiqueta' : 'Add new label';
  String get deleteFailed => _isDe ? 'Löschen fehlgeschlagen' : _isEs ? 'Error al eliminar' : 'Delete failed';
  String get comments => _isDe ? 'Kommentare' : _isEs ? 'Comentarios' : 'Comments';
  String get noComments => _isDe ? 'Keine Kommentare' : _isEs ? 'Sin comentarios' : 'No comments';
  String get writeComment => _isDe ? 'Kommentar schreiben…' : _isEs ? 'Escribe un comentario…' : 'Write a comment…';
  String get reply => _isDe ? 'Antworten …' : _isEs ? 'Responder …' : 'Reply …';
  String get searchPlaceholder => _isDe
      ? 'Titel oder Beschreibung…'
      : _isEs
          ? 'Título o descripción…'
          : 'Title or description…';
  // Card detail
  String get cardLoadFailed => _isDe ? 'Karte konnte nicht geladen werden' : _isEs ? 'No se pudo cargar la tarjeta' : 'Card could not be loaded';
  String get dueDate => _isDe ? 'Fälligkeit' : _isEs ? 'Vencimiento' : 'Due date';
  String get column => _isDe ? 'Liste' : _isEs ? 'Columna' : 'Column';
  String get assigned => _isDe ? 'Zugewiesen' : _isEs ? 'Asignados' : 'Assigned';
  String get attachments => _isDe ? 'Anhänge' : _isEs ? 'Adjuntos' : 'Attachments';
  String get uploadFailed => _isDe ? 'Upload fehlgeschlagen' : _isEs ? 'Error de carga' : 'Upload failed';
  String get fileReadFailed => _isDe ? 'Datei konnte nicht gelesen werden.' : _isEs ? 'No se pudo leer el archivo.' : 'File could not be read.';
  String get uploadNotPossible => _isDe ? 'Upload nicht möglich' : _isEs ? 'Carga no posible' : 'Upload not possible';
  String get missingIds => _isDe ? 'Board- oder Spalten-ID nicht verfügbar.' : _isEs ? 'ID de tablero o columna no disponible.' : 'Board or column ID not available.';
  String get fileAttachFailed => _isDe ? 'Die Datei konnte nicht als Anhang hinzugefügt werden.' : _isEs ? 'No se pudo añadir el archivo como adjunto.' : 'The file could not be added as an attachment.';
  String get noAttachments => _isDe ? 'Keine Anhänge' : _isEs ? 'Sin adjuntos' : 'No attachments';
  String get serverDeniedDeleteAttachment => _isDe
      ? 'Der Server hat das Löschen des Anhangs abgelehnt. Prüfe Berechtigungen oder versuche es in der Web‑Oberfläche.'
      : _isEs
          ? 'El servidor rechazó eliminar el adjunto. Revisa permisos o prueba en la interfaz web.'
          : 'Server denied deleting the attachment. Check permissions or try in web interface.';
  String get share => _isDe ? 'Teilen' : _isEs ? 'Compartir' : 'Share';
  String get systemShare => _isDe ? 'System-Teilen...' : _isEs ? 'Compartir del sistema...' : 'System share...';
  String get copyLink => _isDe ? 'Link kopieren' : _isEs ? 'Copiar enlace' : 'Copy link';
  String get assignTo => _isDe ? 'Zuweisen zu…' : _isEs ? 'Asignar a…' : 'Assign to…';
  String get hint => _isDe ? 'Hinweis' : _isEs ? 'Aviso' : 'Note';

  // Debug / Logs
  String get networkLogs => _isDe ? 'Netzwerk-Logs' : _isEs ? 'Registros de red' : 'Network logs';
  String get noEntries => _isDe ? 'Keine Einträge' : _isEs ? 'Sin entradas' : 'No entries';
  String get delete => _isDe ? 'Löschen' : _isEs ? 'Eliminar' : 'Delete';

  // Sharing
  String get shareBoard => _isDe ? 'Board teilen' : _isEs ? 'Compartir tablero' : 'Share board';
  String get addEllipsis => _isDe ? 'Hinzufügen…' : _isEs ? 'Añadir…' : 'Add…';
  String get shareWith => _isDe ? 'Teilen mit…' : _isEs ? 'Compartir con…' : 'Share with…';
  String get userOrGroupSearch => _isDe ? 'Benutzer oder Gruppe suchen' : _isEs ? 'Buscar usuario o grupo' : 'Search user or group';

  // Labels manage
  String get manageLabels => _isDe ? 'Labels verwalten' : _isEs ? 'Gestionar etiquetas' : 'Manage labels';
  String get editLabel => _isDe ? 'Label bearbeiten' : _isEs ? 'Editar etiqueta' : 'Edit label';
  String get deleteLabelQuestion => _isDe ? 'Label löschen?' : _isEs ? '¿Eliminar etiqueta?' : 'Delete label?';
  String get wordLabel => _isDe ? 'Label' : _isEs ? 'Etiqueta' : 'Label';
  String get save => _isDe ? 'Speichern' : _isEs ? 'Guardar' : 'Save';
  String get colorHexNoHash => _isDe ? 'Farbe (Hex, ohne #)' : _isEs ? 'Color (hex, sin #)' : 'Color (hex, without #)';
  String get exampleHex => _isDe ? 'z. B. 3794ac' : _isEs ? 'p. ej. 3794ac' : 'e.g. 3794ac';

  // Markdown editor
  String get descriptionMarkdown => _isDe ? 'Beschreibung (Markdown)' : _isEs ? 'Descripción (Markdown)' : 'Description (Markdown)';
  String get formatTemplates => _isDe ? 'Formatvorlagen' : _isEs ? 'Plantillas de formato' : 'Format templates';
  String get taskList => _isDe ? 'Aufgabenliste' : _isEs ? 'Lista de tareas' : 'Task list';
  String get close => _isDe ? 'Schließen' : _isEs ? 'Cerrar' : 'Close';
  String get markdownHelp => _isDe ? 'Markdown-Hilfe' : _isEs ? 'Ayuda de Markdown' : 'Markdown help';
  String get helpHeading => _isDe ? 'Überschrift: # Titel' : _isEs ? 'Encabezado: # Título' : 'Heading: # Title';
  String get helpBoldItalic => _isDe ? 'Fett: **Text**    Kursiv: *Text*' : _isEs ? 'Negrita: **texto**    Cursiva: *texto*' : 'Bold: **text**    Italic: *text*';
  String get helpStrike => _isDe ? 'Durchgestrichen: ~~Text~~' : _isEs ? 'Tachado: ~~texto~~' : 'Strikethrough: ~~text~~';
  String get helpCode => _isDe ? 'Code: `inline`    Codeblock: ``` … ```' : _isEs ? 'Código: `inline`    Bloque: ``` … ```' : 'Code: `inline`    Code block: ``` … ```';
  String get helpList => _isDe ? 'Liste: - Punkt' : _isEs ? 'Lista: - ítem' : 'List: - item';
  String get helpTasks => _isDe ? 'Aufgaben: - [ ] offen / - [x] erledigt' : _isEs ? 'Tareas: - [ ] abierta / - [x] hecha' : 'Tasks: - [ ] open / - [x] done';
  String get helpLink => _isDe ? 'Link: [Text](https://example.com)' : _isEs ? 'Enlace: [texto](https://example.com)' : 'Link: [text](https://example.com)';
  String get helpLinebreak => _isDe ? 'Zeilenumbruch: Zeilenende mit zwei Leerzeichen' : _isEs ? 'Salto de línea: dos espacios al final' : 'Linebreak: two spaces at end of line';
  // Insert defaults
  String get mdBold => _isDe ? 'fett' : _isEs ? 'negrita' : 'bold';
  String get mdItalic => _isDe ? 'kursiv' : _isEs ? 'cursiva' : 'italic';
  String get mdStrike => _isDe ? 'durchgestrichen' : _isEs ? 'tachado' : 'strikethrough';
  String get mdCode => _isDe ? 'code' : _isEs ? 'código' : 'code';
  String get mdLinkText => _isDe ? 'Linktext' : _isEs ? 'texto del enlace' : 'link text';
  String get mdListItem => _isDe ? 'Punkt' : _isEs ? 'ítem' : 'item';
  String get mdTask => _isDe ? 'Aufgabe' : _isEs ? 'tarea' : 'task';
  String get mdQuote => _isDe ? 'Zitat' : _isEs ? 'cita' : 'quote';

  // Overview
  String get overview => _isDe ? 'Übersicht' : _isEs ? 'Resumen' : 'Overview';
  String get noBoardsLoaded => _isDe ? 'Keine Boards geladen.' : _isEs ? 'No hay tableros cargados.' : 'No boards loaded.';
  String get activeBoard => _isDe ? 'Standard Board' : _isEs ? 'Tablero predeterminado' : 'Default Board';
  String get moreBoards => _isDe ? 'Weitere Boards' : _isEs ? 'Más tableros' : 'More boards';
  String get yourBoards => _isDe ? 'Deine Boards' : _isEs ? 'Tus tableros' : 'Your boards';
  String get hiddenBoards => _isDe ? 'Ausgeblendete Boards' : _isEs ? 'Tableros ocultos' : 'Hidden boards';
  String loadingBoard(String title) => _isDe ? 'Lade "$title"' : _isEs ? 'Cargando "$title"' : 'Loading "$title"';
  String get columnsLabel => _isDe ? 'Spalten' : _isEs ? 'Columnas' : 'Columns';
  String get cardsLabel => _isDe ? 'Karten' : _isEs ? 'Tarjetas' : 'Cards';
  String get dueSoonLabel => _isDe ? 'Fällig <24h' : _isEs ? 'Vence <24h' : 'Due <24h';
  String get overdueLabel => _isDe ? 'Überfällig' : _isEs ? 'Atrasado' : 'Overdue';
  String get membersLabel => _isDe ? 'Mitglieder' : _isEs ? 'Miembros' : 'Members';

  // Settings
  String get settingsTitle => _isDe ? 'Einstellungen' : _isEs ? 'Ajustes' : 'Settings';
  String get localModeBanner => _isDe
      ? 'Lokaler Modus aktiv: Deine Daten werden nur auf diesem Gerät gespeichert und nicht mit Nextcloud synchronisiert.'
      : _isEs
          ? 'Modo local activo: tus datos se guardan solo en este dispositivo y no se sincronizan con Nextcloud.'
          : 'Local mode active: your data is stored only on this device and not synced to Nextcloud.';
  String get localBoardSection => _isDe ? 'Lokales Board' : _isEs ? 'Tablero local' : 'Local board';
  String get localModeToggleLabel => _isDe ? 'Ohne Anmeldung lokal arbeiten' : _isEs ? 'Trabajar localmente sin iniciar sesión' : 'Work locally without login';
  String get localModeEnableTitle => _isDe ? 'Lokales Board aktivieren?' : _isEs ? '¿Activar tablero local?' : 'Enable local board?';
  String get localModeEnableContent => _isDe
      ? 'Es wird ein lokales Board erstellt. Es erfolgt keine Synchronisierung mit Nextcloud. Du kannst später wieder zu Nextcloud wechseln, indem du die Zugangsdaten erneut hinterlegst.'
      : _isEs
          ? 'Se creará un tablero local. No habrá sincronización con Nextcloud. Puedes volver a Nextcloud más tarde introduciendo tus credenciales nuevamente.'
          : 'A local board will be created. There is no synchronization with Nextcloud. You can switch back later by entering your credentials again.';
  String get enable => _isDe ? 'Aktivieren' : _isEs ? 'Activar' : 'Enable';
  String get nextcloudAccess => _isDe ? 'Konto' : _isEs ? 'Cuenta' : 'Account';
  String get urlPlaceholder => 'cloud.example.com';
  String get username => _isDe ? 'Benutzername' : _isEs ? 'Usuario' : 'Username';
  String get password => _isDe ? 'Passwort' : _isEs ? 'Contraseña' : 'Password';
  String get loginAndLoadBoards => _isDe ? 'Anmeldung testen & Boards laden' : _isEs ? 'Probar inicio y cargar tableros' : 'Test login & load boards';
  String get invalidServerAddress => _isDe
      ? 'Bitte eine gültige Server‑Adresse eingeben (z. B. cloud.example.com oder localhost).'
      : _isEs
          ? 'Introduce una dirección de servidor válida (p. ej., cloud.example.com o localhost).'
          : 'Please enter a valid server address (e.g., cloud.example.com or localhost).';
  String loginSuccessBoards(int count) => _isDe
      ? 'Anmeldung erfolgreich – $count Boards geladen'
      : _isEs
          ? 'Inicio correcto – $count tableros cargados'
          : 'Login successful – $count boards loaded';
  // About
  String get appVersionLabel => _isDe ? 'Version' : _isEs ? 'Versión' : 'Version';
  // Card actions
  String get deleteCard => _isDe ? 'Karte löschen' : _isEs ? 'Eliminar tarjeta' : 'Delete card';
  String get confirmDeleteCard => _isDe ? 'Diese Karte wirklich löschen?' : _isEs ? '¿Eliminar esta tarjeta?' : 'Delete this card?';
  String get markDone => _isDe ? 'Als erledigt markieren' : _isEs ? 'Marcar como hecho' : 'Mark as done';
  String get markUndone => _isDe ? 'Als unerledigt markieren' : _isEs ? 'Marcar como no hecho' : 'Mark as undone';
  String get noDoneListFound => _isDe ? 'Keine "Erledigt"-Liste gefunden' : _isEs ? 'No se encontró lista "Hecho"' : 'No "Done" list found';
  // Boards / Lists
  String get addList => _isDe ? 'Liste hinzufügen' : _isEs ? 'Añadir lista' : 'Add list';
  String get listName => _isDe ? 'Listenname' : _isEs ? 'Nombre de la lista' : 'List name';
  String get addBoard => _isDe ? 'Board hinzufügen' : _isEs ? 'Añadir tablero' : 'Add board';
  String get boardName => _isDe ? 'Boardname' : _isEs ? 'Nombre del tablero' : 'Board name';
  // Search
  String get searchAllBoards => _isDe ? 'Suche in allen Boards' : _isEs ? 'Buscar en todos los tableros' : 'Search all boards';
  // Overview sections
  String get archivedBoards => _isDe ? 'Archivierte Boards' : _isEs ? 'Tableros archivados' : 'Archived boards';
  String get archivedBoardsInfo => _isDe
      ? 'Archivierte Boards können nur in der Nextcloud‑Deck Web‑Oberfläche dearchiviert werden.'
      : _isEs
          ? 'Los tableros archivados solo pueden desarchivarse en la interfaz web de Nextcloud Deck.'
          : 'Archived boards can only be unarchived in the Nextcloud Deck web interface.';
  String get searchingInProgress => _isDe ? 'Suche läuft…' : _isEs ? 'Buscando…' : 'Searching…';
  String searchingBoard(String title) => _isDe ? 'Durchsuche: $title' : _isEs ? 'Buscando: $title' : 'Searching: $title';
  String boardsProgress(int done, int total) => _isDe ? 'Boards: $done / $total' : _isEs ? 'Tableros: $done / $total' : 'Boards: $done / $total';
  String listsProgress(int done, int total) => _isDe ? 'Listen: $done / $total' : _isEs ? 'Listas: $done / $total' : 'Lists: $done / $total';
  String get loginOkNoBoards => _isDe ? 'Login ok – keine Boards gefunden' : _isEs ? 'Inicio ok – no se encontraron tableros' : 'Login ok – no boards found';
  String errorMsg(String msg) => _isDe ? 'Fehler: $msg' : _isEs ? 'Error: $msg' : 'Error: $msg';
  String get activeBoardSection => _isDe ? 'Standard Board' : _isEs ? 'Tablero predeterminado' : 'Default Board';
  String get noBoardsPleaseTest => _isDe ? 'Keine Boards geladen. Bitte Login testen.' : _isEs ? 'No hay tableros cargados. Por favor, prueba el inicio de sesión.' : 'No boards loaded. Please test login.';
  String get appearance => _isDe ? 'Darstellung' : _isEs ? 'Apariencia' : 'Appearance';
  String get darkMode => _isDe ? 'Dark Mode' : _isEs ? 'Modo oscuro' : 'Dark mode';
  String get smartColors => _isDe ? 'Intelligente Farben' : _isEs ? 'Colores inteligentes' : 'Smart colors';
  String get smartColorsHelp => _isDe
      ? 'Wenn aktiviert, passen sich Spaltenhintergründe automatisch der Spaltenbezeichnung an (z. B. "Done" → grün). Wenn deaktiviert, sind Spaltenhintergründe neutral. Kartenfarben bleiben erhalten.'
      : _isEs
          ? 'Si está activado, los fondos de las columnas se ajustan automáticamente al nombre de la columna (p. ej., "Done" → verde). Si está desactivado, los fondos son neutros. Los colores de las tarjetas se mantienen.'
          : 'If enabled, column backgrounds adapt to status keywords (e.g., "Done" → green). If disabled, backgrounds are neutral. Card colors remain.';
  String get showDescriptionAlways => _isDe ? 'Beschreibungstext immer anzeigen' : _isEs ? 'Mostrar siempre la descripción' : 'Always show description';
  String get showDescriptionHelp => _isDe
      ? 'Wenn eingeschaltet, wird der Beschreibungstext auf Karten angezeigt (max. 200 Zeichen). Wenn ausgeschaltet, erscheint stattdessen ein kleines Text-Icon, sofern eine Beschreibung vorhanden ist.'
      : _isEs
          ? 'Si está activado, el texto de descripción se muestra en las tarjetas (máx. 200 caracteres). Si está desactivado, aparece un pequeño icono de texto si hay descripción.'
          : 'If enabled, the description text is shown on cards (max 200 chars). If disabled, a small text icon appears when a description exists.';
  String get developer => _isDe ? 'Entwicklung' : _isEs ? 'Desarrollo' : 'Developer';
  String get enableNetworkLogs => _isDe ? 'Netzwerk-Logs aktivieren' : _isEs ? 'Activar registros de red' : 'Enable network logs';
  String get viewLogs => _isDe ? 'Logs ansehen' : _isEs ? 'Ver registros' : 'View logs';
  String themeLabel(int i) => _isDe ? 'Theme $i' : _isEs ? 'Tema $i' : 'Theme $i';
  // Settings – Performance / Startup
  String get performance => _isDe ? 'Performance' : _isEs ? 'Rendimiento' : 'Performance';
  String get startupPage => _isDe ? 'Startseite' : _isEs ? 'Página de inicio' : 'Startup page';
  String get bgPreloadLabel => _isDe
      ? 'Hintergrund: Spalten vorladen (schont Server, lädt ohne Karten)'
      : _isEs
          ? 'Segundo plano: precargar columnas (ahorra servidor, sin tarjetas)'
          : 'Background: preload columns (saves server, no cards)';
  String get bgPreloadHelp => _isDe
      ? 'Lädt im Hintergrund nur die Spalten (Stacks) aller Boards in den Cache. Karten werden weiterhin nur bei Bedarf geladen.'
      : _isEs
          ? 'Carga en segundo plano solo las columnas (stacks) de todos los tableros en caché. Las tarjetas se cargan bajo demanda.'
          : 'Preloads only columns (stacks) of all boards into cache. Cards still load on demand.';
  String get upcomingProgressHelp => _isDe
      ? 'Hinweis zu „Anstehende Karten“: Die Anzeige neben dem Titel (z. B. 4 / 12) zeigt den Fortschritt eines Hintergrund-Scans über alle Boards. Mit langem Druck auf den Aktualisieren-Button wird ein vollständiger Scan gestartet.'
      : _isEs
          ? 'Nota sobre “Próximas”: La indicación junto al título (p. ej. 4 / 12) muestra el progreso de un escaneo en segundo plano por todos los tableros. Una pulsación larga en actualizar inicia un escaneo completo.'
          : 'Note on “Upcoming”: The indicator next to the title (e.g., 4 / 12) shows background scan progress across all boards. Long-press refresh to run a full scan.';
  String get cacheBoardsLocalLabel => _isDe
      ? 'Boards lokal speichern (schnelles Wiederöffnen, nur geänderte Boards prüfen)'
      : _isEs
          ? 'Guardar tableros localmente (apertura rápida, solo comprobar tableros cambiados)'
          : 'Store boards locally (fast reopen, only check changed boards)';
  String get cacheBoardsLocalHelp => _isDe
      ? 'Speichert Boards lokal und nutzt ETags, um beim Start nur geänderte Boards neu zu prüfen. Deaktivieren, wenn dein Server keine ETags liefert.'
      : _isEs
          ? 'Guarda los tableros localmente y usa ETags para comprobar solo los tableros cambiados al iniciar. Desactívalo si tu servidor no proporciona ETags.'
          : 'Stores boards locally and uses ETags to check only changed boards on launch. Disable if your server does not provide ETags.';
  // Overview – cache indicator
  String get cacheLabel => _isDe ? 'Cache' : _isEs ? 'Caché' : 'Cache';
  // Language
  String get language => _isDe ? 'Sprache' : _isEs ? 'Idioma' : 'Language';
  String get systemLanguage => _isDe ? 'System' : _isEs ? 'Sistema' : 'System';
  String get german => _isDe ? 'Deutsch' : _isEs ? 'Alemán' : 'German';
  String get english => _isDe ? 'Englisch' : _isEs ? 'Inglés' : 'English';
  String get spanish => _isDe ? 'Spanisch' : _isEs ? 'Español' : 'Spanish';
  // Security / Network
  String get httpsEnforcedInfo => _isDe
      ? 'Next Deck nutzt immer HTTPS. Kein Protokoll (http/https) eingeben.'
      : _isEs
          ? 'Next Deck usa siempre HTTPS. No introduzcas protocolo (http/https).'
          : 'Next Deck always uses HTTPS. Do not enter a protocol (http/https).';
  // Navigation
  String get navUpcoming => _isDe ? 'Anstehend' : _isEs ? 'Próximas' : 'Upcoming';
  String get upcomingTitle => _isDe ? 'Anstehende Karten' : _isEs ? 'Tarjetas próximas' : 'Upcoming cards';
  String get noDueCards => _isDe ? 'Keine fälligen Karten' : _isEs ? 'No hay tarjetas con vencimiento' : 'No due cards';
  String get navBoard => _isDe ? 'Board' : _isEs ? 'Tablero' : 'Board';
  // Upcoming sections
  String get today => _isDe ? 'Heute' : _isEs ? 'Hoy' : 'Today';
  String get tomorrow => _isDe ? 'Morgen' : _isEs ? 'Mañana' : 'Tomorrow';
  String get next7Days => _isDe ? 'Nächste 7 Tage' : _isEs ? 'Próximos 7 días' : 'Next 7 days';
  String get later => _isDe ? 'Später' : _isEs ? 'Más tarde' : 'Later';
}

class _L10nDelegate extends LocalizationsDelegate<L10n> {
  const _L10nDelegate();
  @override
  bool isSupported(Locale locale) {
    final l = locale.languageCode.toLowerCase();
    return l == 'de' || l == 'en' || l == 'es';
  }

  @override
  Future<L10n> load(Locale locale) async => L10n(locale);

  @override
  bool shouldReload(covariant LocalizationsDelegate<L10n> old) => false;
}
