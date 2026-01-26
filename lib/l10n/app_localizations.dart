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

  String get search => _isDe
      ? 'Suchen'
      : _isEs
          ? 'Buscar'
          : 'Search';
  String searchInBoard(String title) => _isDe
      ? 'Suchen im Board $title'
      : _isEs
          ? 'Buscar en el tablero $title'
          : 'Search in board $title';
  String get searchScopeCurrent => _isDe
      ? 'Aktuelles Board'
      : _isEs
          ? 'Tablero actual'
          : 'Current board';
  String get searchScopeAll => _isDe
      ? 'Alle Boards'
      : _isEs
          ? 'Todos los tableros'
          : 'All boards';

  String get newCard => _isDe
      ? 'Neue Karte'
      : _isEs
          ? 'Nueva tarjeta'
          : 'New card';
  String get title => _isDe
      ? 'Titel'
      : _isEs
          ? 'Título'
          : 'Title';
  String get create => _isDe
      ? 'Erstellen'
      : _isEs
          ? 'Crear'
          : 'Create';
  String get cancel => _isDe
      ? 'Abbrechen'
      : _isEs
          ? 'Cancelar'
          : 'Cancel';
  String get ok => 'OK';
  String get selectColumn => _isDe
      ? 'Liste auswählen'
      : _isEs
          ? 'Seleccionar columna'
          : 'Select column';
  String get refresh => _isDe
      ? 'Aktualisieren'
      : _isEs
          ? 'Actualizar'
          : 'Refresh';
  String get showArchivedCards => _isDe
      ? 'Archivierte Karten anzeigen'
      : _isEs
          ? 'Mostrar tarjetas archivadas'
          : 'Show archived cards';
  String get showActiveCards => _isDe
      ? 'Aktive Karten anzeigen'
      : _isEs
          ? 'Mostrar tarjetas activas'
          : 'Show active cards';
  String get pleaseSelectBoard => _isDe
      ? 'Bitte Board in den Einstellungen auswählen.'
      : _isEs
          ? 'Seleccione un tablero en ajustes.'
          : 'Please select a board in settings.';
  String get move => _isDe
      ? 'Verschieben'
      : _isEs
          ? 'Mover'
          : 'Move';
  String get labels => _isDe
      ? 'Labels'
      : _isEs
          ? 'Etiquetas'
          : 'Labels';
  String get labelsCaption => _isDe
      ? 'Schlagworte'
      : _isEs
          ? 'Etiquetas'
          : 'Tags';
  String get newLabel => _isDe
      ? 'Neues Label'
      : _isEs
          ? 'Nueva etiqueta'
          : 'New label';
  String get addNewLabel => _isDe
      ? 'Neues Label hinzufügen'
      : _isEs
          ? 'Añadir nueva etiqueta'
          : 'Add new label';
  String get deleteFailed => _isDe
      ? 'Löschen fehlgeschlagen'
      : _isEs
          ? 'Error al eliminar'
          : 'Delete failed';
  String get comments => _isDe
      ? 'Kommentare'
      : _isEs
          ? 'Comentarios'
          : 'Comments';
  String get noComments => _isDe
      ? 'Keine Kommentare'
      : _isEs
          ? 'Sin comentarios'
          : 'No comments';
  String get writeComment => _isDe
      ? 'Kommentar schreiben…'
      : _isEs
          ? 'Escribe un comentario…'
          : 'Write a comment…';
  String get reply => _isDe
      ? 'Antworten …'
      : _isEs
          ? 'Responder …'
          : 'Reply …';
  String get searchPlaceholder => _isDe
      ? 'Titel oder Beschreibung…'
      : _isEs
          ? 'Título o descripción…'
          : 'Title or description…';
  // Card detail
  String get cardLoadFailed => _isDe
      ? 'Karte konnte nicht geladen werden'
      : _isEs
          ? 'No se pudo cargar la tarjeta'
          : 'Card could not be loaded';
  String get card => _isDe
      ? 'Karte'
      : _isEs
          ? 'Tarjeta'
          : 'Card';
  String get dueDate => _isDe
      ? 'Fälligkeit'
      : _isEs
          ? 'Vencimiento'
          : 'Due date';
  String get timeLabel => _isDe
      ? 'Uhrzeit'
      : _isEs
          ? 'Hora'
          : 'Time';
  String get column => _isDe
      ? 'Liste'
      : _isEs
          ? 'Columna'
          : 'Column';
  String get assigned => _isDe
      ? 'Zugewiesen'
      : _isEs
          ? 'Asignados'
          : 'Assigned';
  String get attachments => _isDe
      ? 'Anhänge'
      : _isEs
          ? 'Adjuntos'
          : 'Attachments';
  String get addAttachment => _isDe
      ? 'Anhang hinzufügen'
      : _isEs
          ? 'Añadir adjunto'
          : 'Add attachment';
  String get photoLibrary => _isDe
      ? 'Fotomediathek'
      : _isEs
          ? 'Fototeca'
          : 'Photo library';
  String get files => _isDe
      ? 'Dateien'
      : _isEs
          ? 'Archivos'
          : 'Files';
  String get attachmentFallback => _isDe
      ? 'Anhang'
      : _isEs
          ? 'Adjunto'
          : 'Attachment';
  String get uploadFailed => _isDe
      ? 'Upload fehlgeschlagen'
      : _isEs
          ? 'Error de carga'
          : 'Upload failed';
  String get fileReadFailed => _isDe
      ? 'Datei konnte nicht gelesen werden.'
      : _isEs
          ? 'No se pudo leer el archivo.'
          : 'File could not be read.';
  String get uploadNotPossible => _isDe
      ? 'Upload nicht möglich'
      : _isEs
          ? 'Carga no posible'
          : 'Upload not possible';
  String get missingIds => _isDe
      ? 'Board- oder Listen-ID nicht verfügbar.'
      : _isEs
          ? 'ID de tablero o columna no disponible.'
          : 'Board or column ID not available.';
  String get fileAttachFailed => _isDe
      ? 'Die Datei konnte nicht als Anhang hinzugefügt werden.'
      : _isEs
          ? 'No se pudo añadir el archivo como adjunto.'
          : 'The file could not be added as an attachment.';
  String get noAttachments => _isDe
      ? 'Keine Anhänge'
      : _isEs
          ? 'Sin adjuntos'
          : 'No attachments';
  String get serverDeniedDeleteAttachment => _isDe
      ? 'Der Server hat das Löschen des Anhangs abgelehnt. Prüfe Berechtigungen oder versuche es in der Web‑Oberfläche.'
      : _isEs
          ? 'El servidor rechazó eliminar el adjunto. Revisa permisos o prueba en la interfaz web.'
          : 'Server denied deleting the attachment. Check permissions or try in web interface.';
  String get share => _isDe
      ? 'Teilen'
      : _isEs
          ? 'Compartir'
          : 'Share';
  String get systemShare => _isDe
      ? 'System-Teilen...'
      : _isEs
          ? 'Compartir del sistema...'
          : 'System share...';
  String get copyLink => _isDe
      ? 'Link kopieren'
      : _isEs
          ? 'Copiar enlace'
          : 'Copy link';
  String get assignTo => _isDe
      ? 'Zuweisen zu…'
      : _isEs
          ? 'Asignar a…'
          : 'Assign to…';
  String get hint => _isDe
      ? 'Hinweis'
      : _isEs
          ? 'Aviso'
          : 'Note';

  // Debug / Logs
  String get networkLogs => _isDe
      ? 'Netzwerk-Logs'
      : _isEs
          ? 'Registros de red'
          : 'Network logs';
  String get noEntries => _isDe
      ? 'Keine Einträge'
      : _isEs
          ? 'Sin entradas'
          : 'No entries';
  String get delete => _isDe
      ? 'Löschen'
      : _isEs
          ? 'Eliminar'
          : 'Delete';

  // Sharing
  String get shareBoard => _isDe
      ? 'Board teilen'
      : _isEs
          ? 'Compartir tablero'
          : 'Share board';
  String get addEllipsis => _isDe
      ? 'Hinzufügen…'
      : _isEs
          ? 'Añadir…'
          : 'Add…';
  String get shareWith => _isDe
      ? 'Teilen mit…'
      : _isEs
          ? 'Compartir con…'
          : 'Share with…';
  String get userOrGroupSearch => _isDe
      ? 'Benutzer oder Gruppe suchen'
      : _isEs
          ? 'Buscar usuario o grupo'
          : 'Search user or group';

  // Labels manage
  String get manageLabels => _isDe
      ? 'Labels verwalten'
      : _isEs
          ? 'Gestionar etiquetas'
          : 'Manage labels';
  String get editLabel => _isDe
      ? 'Label bearbeiten'
      : _isEs
          ? 'Editar etiqueta'
          : 'Edit label';
  String get deleteLabelQuestion => _isDe
      ? 'Label löschen?'
      : _isEs
          ? '¿Eliminar etiqueta?'
          : 'Delete label?';
  String get wordLabel => _isDe
      ? 'Label'
      : _isEs
          ? 'Etiqueta'
          : 'Label';
  String get save => _isDe
      ? 'Speichern'
      : _isEs
          ? 'Guardar'
          : 'Save';
  String get colorHexNoHash => _isDe
      ? 'Farbe (Hex, ohne #)'
      : _isEs
          ? 'Color (hex, sin #)'
          : 'Color (hex, without #)';
  String get exampleHex => _isDe
      ? 'z. B. 3794ac'
      : _isEs
          ? 'p. ej. 3794ac'
          : 'e.g. 3794ac';

  // Markdown editor
  String get descriptionMarkdown => _isDe
      ? 'Beschreibung (Markdown)'
      : _isEs
          ? 'Descripción (Markdown)'
          : 'Description (Markdown)';
  String get formatTemplates => _isDe
      ? 'Formatvorlagen'
      : _isEs
          ? 'Plantillas de formato'
          : 'Format templates';
  String get taskList => _isDe
      ? 'Aufgabenliste'
      : _isEs
          ? 'Lista de tareas'
          : 'Task list';
  String get close => _isDe
      ? 'Schließen'
      : _isEs
          ? 'Cerrar'
          : 'Close';
  String get markdownHelp => _isDe
      ? 'Markdown-Hilfe'
      : _isEs
          ? 'Ayuda de Markdown'
          : 'Markdown help';
  String get helpHeading => _isDe
      ? 'Überschrift: # Titel'
      : _isEs
          ? 'Encabezado: # Título'
          : 'Heading: # Title';
  String get helpBoldItalic => _isDe
      ? 'Fett: **Text**    Kursiv: *Text*'
      : _isEs
          ? 'Negrita: **texto**    Cursiva: *texto*'
          : 'Bold: **text**    Italic: *text*';
  String get helpStrike => _isDe
      ? 'Durchgestrichen: ~~Text~~'
      : _isEs
          ? 'Tachado: ~~texto~~'
          : 'Strikethrough: ~~text~~';
  String get helpCode => _isDe
      ? 'Code: `inline`    Codeblock: ``` … ```'
      : _isEs
          ? 'Código: `inline`    Bloque: ``` … ```'
          : 'Code: `inline`    Code block: ``` … ```';
  String get helpList => _isDe
      ? 'Liste: - Punkt'
      : _isEs
          ? 'Lista: - ítem'
          : 'List: - item';
  String get helpTasks => _isDe
      ? 'Aufgaben: - [ ] offen / - [x] erledigt'
      : _isEs
          ? 'Tareas: - [ ] abierta / - [x] hecha'
          : 'Tasks: - [ ] open / - [x] done';
  String get helpLink => _isDe
      ? 'Link: [Text](https://example.com)'
      : _isEs
          ? 'Enlace: [texto](https://example.com)'
          : 'Link: [text](https://example.com)';
  String get helpLinebreak => _isDe
      ? 'Zeilenumbruch: Zeilenende mit zwei Leerzeichen'
      : _isEs
          ? 'Salto de línea: dos espacios al final'
          : 'Linebreak: two spaces at end of line';
  // Insert defaults
  String get mdBold => _isDe
      ? 'fett'
      : _isEs
          ? 'negrita'
          : 'bold';
  String get mdItalic => _isDe
      ? 'kursiv'
      : _isEs
          ? 'cursiva'
          : 'italic';
  String get mdStrike => _isDe
      ? 'durchgestrichen'
      : _isEs
          ? 'tachado'
          : 'strikethrough';
  String get mdCode => _isDe
      ? 'code'
      : _isEs
          ? 'código'
          : 'code';
  String get mdLinkText => _isDe
      ? 'Linktext'
      : _isEs
          ? 'texto del enlace'
          : 'link text';
  String get mdListItem => _isDe
      ? 'Punkt'
      : _isEs
          ? 'ítem'
          : 'item';
  String get mdTask => _isDe
      ? 'Aufgabe'
      : _isEs
          ? 'tarea'
          : 'task';
  String get mdQuote => _isDe
      ? 'Zitat'
      : _isEs
          ? 'cita'
          : 'quote';

  // Overview
  String get overview => _isDe
      ? 'Übersicht'
      : _isEs
          ? 'Resumen'
          : 'Overview';
  String get noBoardsLoaded => _isDe
      ? 'Keine Boards geladen.'
      : _isEs
          ? 'No hay tableros cargados.'
          : 'No boards loaded.';
  String get boardActions => _isDe
      ? 'Board-Aktionen'
      : _isEs
          ? 'Acciones del tablero'
          : 'Board actions';
  String get changeBoardColor => _isDe
      ? 'Board-Farbe ändern'
      : _isEs
          ? 'Cambiar color del tablero'
          : 'Change board color';
  String get pickColor => _isDe
      ? 'Farbe auswählen'
      : _isEs
          ? 'Seleccionar color'
          : 'Pick a color';
  String get boardColorDefault => _isDe
      ? 'Standardfarbe'
      : _isEs
          ? 'Color estándar'
          : 'Default color';
  String get newBoard => _isDe
      ? 'Neues Board'
      : _isEs
          ? 'Nuevo tablero'
          : 'New board';
  String get newColumn => _isDe
      ? 'Neue Liste'
      : _isEs
          ? 'Nueva columna'
          : 'New column';
  String get reorderColumns => _isDe
      ? 'Listen sortieren'
      : _isEs
          ? 'Ordenar columnas'
          : 'Reorder columns';
  String reorderColumnsFor(String title) => _isDe
      ? 'Listen: $title'
      : _isEs
          ? 'Columnas: $title'
          : 'Columns: $title';
  String get selectBoard => _isDe
      ? 'Board auswählen'
      : _isEs
          ? 'Seleccionar tablero'
          : 'Select board';
  String get boardTitlePlaceholder => _isDe
      ? 'Board-Titel'
      : _isEs
          ? 'Título del tablero'
          : 'Board title';
  String get columnTitlePlaceholder => _isDe
      ? 'Listen-Titel'
      : _isEs
          ? 'Título de columna'
          : 'Column title';
  String get deleteColumn => _isDe
      ? 'Liste löschen'
      : _isEs
          ? 'Eliminar columna'
          : 'Delete column';
  String deleteColumnQuestion(String title) => _isDe
      ? 'Liste "$title" wirklich löschen?'
      : _isEs
          ? '¿Eliminar la columna "$title"?'
          : 'Delete column "$title"?';
  String get columnDeleteFailed => _isDe
      ? 'Liste konnte nicht gelöscht werden'
      : _isEs
          ? 'No se pudo eliminar la columna'
          : 'Column could not be deleted';
  String get boardCreateFailed => _isDe
      ? 'Board konnte nicht erstellt werden'
      : _isEs
          ? 'No se pudo crear el tablero'
          : 'Board could not be created';
  String get boardUpdateFailed => _isDe
      ? 'Board konnte nicht aktualisiert werden'
      : _isEs
          ? 'No se pudo actualizar el tablero'
          : 'Board could not be updated';
  String get columnCreateFailed => _isDe
      ? 'Liste konnte nicht erstellt werden'
      : _isEs
          ? 'No se pudo crear la columna'
          : 'Column could not be created';
  String get noColumnsLoaded => _isDe
      ? 'Keine Listen geladen.'
      : _isEs
          ? 'No hay columnas cargadas.'
          : 'No columns loaded.';
  String get activeBoard => _isDe
      ? 'Standard Board'
      : _isEs
          ? 'Tablero predeterminado'
          : 'Default Board';
  String get moreBoards => _isDe
      ? 'Weitere Boards'
      : _isEs
          ? 'Más tableros'
          : 'More boards';
  String get yourBoards => _isDe
      ? 'Deine Boards'
      : _isEs
          ? 'Tus tableros'
          : 'Your boards';
  String get status => _isDe
      ? 'Status'
      : _isEs
          ? 'Estado'
          : 'Status';
  String get hiddenBoards => _isDe
      ? 'Ausgeblendete Boards'
      : _isEs
          ? 'Tableros ocultos'
          : 'Hidden boards';
  String loadingBoard(String title) => _isDe
      ? 'Lade "$title"'
      : _isEs
          ? 'Cargando "$title"'
          : 'Loading "$title"';
  String get columnsLabel => _isDe
      ? 'Listen'
      : _isEs
          ? 'Columnas'
          : 'Columns';
  String get cardsLabel => _isDe
      ? 'Karten'
      : _isEs
          ? 'Tarjetas'
          : 'Cards';
  String get dueSoonLabel => _isDe
      ? 'Fällig <24h'
      : _isEs
          ? 'Vence <24h'
          : 'Due <24h';
  String get overdueLabel => _isDe
      ? 'Überfällig'
      : _isEs
          ? 'Atrasado'
          : 'Overdue';
  String get membersLabel => _isDe
      ? 'Mitglieder'
      : _isEs
          ? 'Miembros'
          : 'Members';
  String get notifications => _isDe
      ? 'Benachrichtigungen'
      : _isEs
          ? 'Notificaciones'
          : 'Notifications';
  String get dueNotificationsEnable => _isDe
      ? 'Fälligkeits-Erinnerungen'
      : _isEs
          ? 'Recordatorios de vencimiento'
          : 'Due reminders';
  String get dueNotificationsHelp => _isDe
      ? 'Erinnert dich vor Fälligkeit und optional bei Überfälligkeit.'
      : _isEs
          ? 'Te recuerda antes del vencimiento y opcionalmente cuando está atrasado.'
          : 'Reminds you before due date and optionally when overdue.';
  String get reminder1hBefore => _isDe
      ? '1 Stunde vorher'
      : _isEs
          ? '1 hora antes'
          : '1 hour before';
  String get reminder1dBefore => _isDe
      ? '1 Tag vorher'
      : _isEs
          ? '1 día antes'
          : '1 day before';
  String get overdueReminderToggle => _isDe
      ? 'Überfällig erinnern'
      : _isEs
          ? 'Recordatorio de atraso'
          : 'Overdue reminder';
  String get reminderIn1Hour => _isDe
      ? 'in 1 Stunde'
      : _isEs
          ? 'en 1 hora'
          : 'in 1 hour';
  String get reminderIn1Day => _isDe
      ? 'in 1 Tag'
      : _isEs
          ? 'en 1 día'
          : 'in 1 day';
  String dueReminderTitle(String when) => _isDe
      ? 'Fällig $when'
      : _isEs
          ? 'Vence $when'
          : 'Due $when';
  String get overdueReminderTitle => _isDe
      ? 'Überfällig'
      : _isEs
          ? 'Atrasado'
          : 'Overdue';

  // Settings
  String get settingsTitle => _isDe
      ? 'Einstellungen'
      : _isEs
          ? 'Ajustes'
          : 'Settings';
  String get localModeBanner => _isDe
      ? 'Lokaler Modus aktiv: Deine Daten werden nur auf diesem Gerät gespeichert und nicht mit Nextcloud synchronisiert.'
      : _isEs
          ? 'Modo local activo: tus datos se guardan solo en este dispositivo y no se sincronizan con Nextcloud.'
          : 'Local mode active: your data is stored only on this device and not synced to Nextcloud.';
  String get localBoardSection => _isDe
      ? 'Lokales Board'
      : _isEs
          ? 'Tablero local'
          : 'Local board';
  String get localModeToggleLabel => _isDe
      ? 'Ohne Anmeldung lokal arbeiten'
      : _isEs
          ? 'Trabajar localmente sin iniciar sesión'
          : 'Work locally without login';
  String get localModeEnableTitle => _isDe
      ? 'Lokales Board aktivieren?'
      : _isEs
          ? '¿Activar tablero local?'
          : 'Enable local board?';
  String get localModeEnableContent => _isDe
      ? 'Es wird ein lokales Board erstellt. Es erfolgt keine Synchronisierung mit Nextcloud. Du kannst später wieder zu Nextcloud wechseln, indem du die Zugangsdaten erneut hinterlegst.'
      : _isEs
          ? 'Se creará un tablero local. No habrá sincronización con Nextcloud. Puedes volver a Nextcloud más tarde introduciendo tus credenciales nuevamente.'
          : 'A local board will be created. There is no synchronization with Nextcloud. You can switch back later by entering your credentials again.';
  String get enable => _isDe
      ? 'Aktivieren'
      : _isEs
          ? 'Activar'
          : 'Enable';
  String get nextcloudAccess => _isDe
      ? 'Konto'
      : _isEs
          ? 'Cuenta'
          : 'Account';
  String get urlPlaceholder => 'cloud.example.com';
  String get username => _isDe
      ? 'Benutzername'
      : _isEs
          ? 'Usuario'
          : 'Username';
  String get password => _isDe
      ? 'Passwort'
      : _isEs
          ? 'Contraseña'
          : 'Password';
  String get appPassword => _isDe
      ? 'App‑Passwort'
      : _isEs
          ? 'Contraseña de aplicación'
          : 'App password';
  String get appPasswordHint => _isDe
      ? 'Bei aktivierter Zwei‑Faktor‑Authentifizierung bitte in Nextcloud unter Einstellungen → Sicherheit ein App‑Passwort erzeugen und hier eintragen.'
      : _isEs
          ? 'Si tienes activada la verificación en dos pasos, crea una contraseña de aplicación en Nextcloud (Ajustes → Seguridad) y escríbela aquí.'
          : 'If two‑factor authentication is enabled, create an app password in Nextcloud (Settings → Security) and enter it here.';
  String get loginAndLoadBoards => _isDe
      ? 'Anmeldung testen & Boards laden'
      : _isEs
          ? 'Probar inicio y cargar tableros'
          : 'Test login & load boards';
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
  String initialSyncStarting(int count) => _isDe
      ? 'Initialer Abgleich läuft… ($count Boards)'
      : _isEs
          ? 'Sincronización inicial en curso… ($count tableros)'
          : 'Initial sync running… ($count boards)';
  String initialSyncProgress(int done, int total) => _isDe
      ? 'Initialer Abgleich: $done / $total'
      : _isEs
          ? 'Sincronización inicial: $done / $total'
          : 'Initial sync: $done / $total';
  String initialSyncDone(int count) => _isDe
      ? 'Initialer Abgleich abgeschlossen – $count Boards bereit'
      : _isEs
          ? 'Sincronización inicial terminada: $count tableros listos'
          : 'Initial sync finished – $count boards ready';
  // About
  String get appVersionLabel => _isDe
      ? 'Version'
      : _isEs
          ? 'Versión'
          : 'Version';
  // Card actions
  String get deleteCard => _isDe
      ? 'Karte löschen'
      : _isEs
          ? 'Eliminar tarjeta'
          : 'Delete card';
  String get confirmDeleteCard => _isDe
      ? 'Diese Karte wirklich löschen?'
      : _isEs
          ? '¿Eliminar esta tarjeta?'
          : 'Delete this card?';
  String get markDone => _isDe
      ? 'Als erledigt markieren'
      : _isEs
          ? 'Marcar como hecho'
          : 'Mark as done';
  String get markUndone => _isDe
      ? 'Als unerledigt markieren'
      : _isEs
          ? 'Marcar como no hecho'
          : 'Mark as undone';
  String get archiveCard => _isDe
      ? 'Karte archivieren'
      : _isEs
          ? 'Archivar tarjeta'
          : 'Archive card';
  String get unarchiveCard => _isDe
      ? 'Karte dearchivieren'
      : _isEs
          ? 'Desarchivar tarjeta'
          : 'Unarchive card';
  String get noDoneListFound => _isDe
      ? 'Keine "Erledigt"-Liste gefunden'
      : _isEs
          ? 'No se encontró lista "Hecho"'
          : 'No "Done" list found';
  // Boards / Lists
  String get addList => _isDe
      ? 'Liste hinzufügen'
      : _isEs
          ? 'Añadir lista'
          : 'Add list';
  String get listName => _isDe
      ? 'Listenname'
      : _isEs
          ? 'Nombre de la lista'
          : 'List name';
  String get addBoard => _isDe
      ? 'Board hinzufügen'
      : _isEs
          ? 'Añadir tablero'
          : 'Add board';
  String get boardName => _isDe
      ? 'Boardname'
      : _isEs
          ? 'Nombre del tablero'
          : 'Board name';
  // Search
  String get searchAllBoards => _isDe
      ? 'Suche in allen Boards'
      : _isEs
          ? 'Buscar en todos los tableros'
          : 'Search all boards';
  // Overview sections
  String get archivedBoards => _isDe
      ? 'Archivierte Boards'
      : _isEs
          ? 'Tableros archivados'
          : 'Archived boards';
  String get archivedBoardsInfo => _isDe
      ? 'Archivierte Boards können nur in der Nextcloud‑Deck Web‑Oberfläche dearchiviert werden.'
      : _isEs
          ? 'Los tableros archivados solo pueden desarchivarse en la interfaz web de Nextcloud Deck.'
          : 'Archived boards can only be unarchived in the Nextcloud Deck web interface.';
  String get searchingInProgress => _isDe
      ? 'Suche läuft…'
      : _isEs
          ? 'Buscando…'
          : 'Searching…';
  String searchingBoard(String title) => _isDe
      ? 'Durchsuche: $title'
      : _isEs
          ? 'Buscando: $title'
          : 'Searching: $title';
  String boardsProgress(int done, int total) => _isDe
      ? 'Boards: $done / $total'
      : _isEs
          ? 'Tableros: $done / $total'
          : 'Boards: $done / $total';
  String listsProgress(int done, int total) => _isDe
      ? 'Listen: $done / $total'
      : _isEs
          ? 'Listas: $done / $total'
          : 'Lists: $done / $total';
  String get loginOkNoBoards => _isDe
      ? 'Login ok – keine Boards gefunden'
      : _isEs
          ? 'Inicio ok – no se encontraron tableros'
          : 'Login ok – no boards found';
  String errorMsg(String msg) => _isDe
      ? 'Fehler: $msg'
      : _isEs
          ? 'Error: $msg'
          : 'Error: $msg';
  String get activeBoardSection => _isDe
      ? 'Standard Board'
      : _isEs
          ? 'Tablero predeterminado'
          : 'Default Board';
  String get startupBoardChoice => _isDe
      ? 'Beim Start laden'
      : _isEs
          ? 'Al iniciar cargar'
          : 'On launch load';
  String get startupBoardDefault => _isDe
      ? 'Standard‑Board'
      : _isEs
          ? 'Tablero predeterminado'
          : 'Default board';
  String get startupBoardLast => _isDe
      ? 'Zuletzt aktives Board'
      : _isEs
          ? 'Último tablero activo'
          : 'Last active board';
  String get startupBoardHelp => _isDe
      ? 'Wähle, welches Board beim App‑Start geöffnet wird.'
      : _isEs
          ? 'Elige qué tablero se abre al iniciar la app.'
          : 'Choose which board opens when the app starts.';
  String get noBoardsPleaseTest => _isDe
      ? 'Keine Boards geladen. Bitte Login testen.'
      : _isEs
          ? 'No hay tableros cargados. Por favor, prueba el inicio de sesión.'
          : 'No boards loaded. Please test login.';
  String get appearance => _isDe
      ? 'Darstellung'
      : _isEs
          ? 'Apariencia'
          : 'Appearance';
  String get themeMode => _isDe
      ? 'Theme'
      : _isEs
          ? 'Tema'
          : 'Theme';
  String get themeModeHelp => _isDe
      ? 'Hell/Dunkel sind fest. „System“ folgt automatisch dem System-Theme.'
      : _isEs
          ? 'Claro/Oscuro son fijos. “Sistema” sigue el tema del sistema.'
          : 'Light/Dark are fixed. “System” follows the system theme.';
  String get themeLight => _isDe
      ? 'Hell'
      : _isEs
          ? 'Claro'
          : 'Light';
  String get themeDark => _isDe
      ? 'Dunkel'
      : _isEs
          ? 'Oscuro'
          : 'Dark';
  String get themeSystem => _isDe
      ? 'System'
      : _isEs
          ? 'Sistema'
          : 'System';
  String get boardBandMode => _isDe
      ? 'Hintergrundband zwischen Listen'
      : _isEs
          ? 'Banda de fondo entre columnas'
          : 'Background band between columns';
  String get boardBandNextcloud => _isDe
      ? 'Nextcloud-Farbe'
      : _isEs
          ? 'Color de Nextcloud'
          : 'Nextcloud color';
  String get boardBandHidden => _isDe
      ? 'Ausblenden'
      : _isEs
          ? 'Ocultar'
          : 'Hidden';
  String get boardBandHelp => _isDe
      ? 'Legt fest, ob das Hintergrundband die Board-Farbe aus Nextcloud nutzt oder ausgeblendet wird.'
      : _isEs
          ? 'Controla si la banda de fondo usa el color del tablero de Nextcloud o se oculta.'
          : 'Controls whether the background band uses the board color from Nextcloud or is hidden.';
  String get smartColors => _isDe
      ? 'Intelligente Farben'
      : _isEs
          ? 'Colores inteligentes'
          : 'Smart colors';
  String get smartColorsHelp => _isDe
      ? 'Wenn aktiviert, passen sich Listenhintergründe automatisch der Listenbezeichnung an (z. B. "Done" → grün). Wenn deaktiviert, sind Listenhintergründe neutral. Kartenfarben werden separat eingestellt.'
      : _isEs
          ? 'Si está activado, los fondos de las columnas se ajustan automáticamente al nombre de la columna (p. ej., "Done" → verde). Si está desactivado, los fondos son neutros. Los colores de las tarjetas se configuran por separado.'
          : 'If enabled, column backgrounds adapt to status keywords (e.g., "Done" → green). If disabled, backgrounds are neutral. Card colors are configured separately.';
  String get cardColorsFromLabels => _isDe
      ? 'Kartenfarben aus Labels'
      : _isEs
          ? 'Colores de tarjetas desde etiquetas'
          : 'Card colors from labels';
  String get cardColorsFromLabelsHelp => _isDe
      ? 'Wenn aktiviert, nutzen Karten die Farbe des ersten Labels. Wenn deaktiviert, sind Karten neutral gefärbt.'
      : _isEs
          ? 'Si está activado, las tarjetas usan el color de la primera etiqueta. Si está desactivado, las tarjetas son neutras.'
          : 'If enabled, cards use the first label color. If disabled, cards are neutral.';
  String get descriptionLabel => _isDe
      ? 'Beschreibung'
      : _isEs
          ? 'Descripción'
          : 'Description';
  String get showDescriptionAlways => _isDe
      ? 'Beschreibungstext immer anzeigen'
      : _isEs
          ? 'Mostrar siempre la descripción'
          : 'Always show description';
  String get descriptionPlaceholder => _isDe
      ? 'Beschreibung (Markdown, wie in Nextcloud Deck)'
      : _isEs
          ? 'Descripción (Markdown, como en Nextcloud Deck)'
          : 'Description (Markdown, like in Nextcloud Deck)';
  String get showDescriptionHelp => _isDe
      ? 'Wenn eingeschaltet, wird der Beschreibungstext auf Karten angezeigt (max. 200 Zeichen). Wenn ausgeschaltet, erscheint stattdessen ein kleines Text-Icon, sofern eine Beschreibung vorhanden ist.'
      : _isEs
          ? 'Si está activado, el texto de descripción se muestra en las tarjetas (máx. 200 caracteres). Si está desactivado, aparece un pequeño icono de texto si hay descripción.'
          : 'If enabled, the description text is shown on cards (max 200 chars). If disabled, a small text icon appears when a description exists.';
  String get removeDate => _isDe
      ? 'Datum entfernen'
      : _isEs
          ? 'Eliminar fecha'
          : 'Remove date';
  String get overviewShowBoardInfo => _isDe
      ? 'Informationen der Boards in Übersicht anzeigen'
      : _isEs
          ? 'Mostrar información de los tableros en el resumen'
          : 'Show board information in overview';
  String get overviewShowBoardInfoHelp => _isDe
      ? 'Bei vielen Boards abschalten, um die Ladegeschwindigkeit der Übersicht zu verbessern.'
      : _isEs
          ? 'Desactívalo con muchos tableros para mejorar la velocidad de carga del resumen.'
          : 'Disable with many boards to improve overview loading speed.';
  String get developer => _isDe
      ? 'Entwicklung'
      : _isEs
          ? 'Desarrollo'
          : 'Developer';
  String get enableNetworkLogs => _isDe
      ? 'Netzwerk-Logs aktivieren'
      : _isEs
          ? 'Activar registros de red'
          : 'Enable network logs';
  String get viewLogs => _isDe
      ? 'Logs ansehen'
      : _isEs
          ? 'Ver registros'
          : 'View logs';
  String themeLabel(int i) => _isDe
      ? 'Theme $i'
      : _isEs
          ? 'Tema $i'
          : 'Theme $i';
  // Settings – Performance / Startup
  String get performance => _isDe
      ? 'Performance'
      : _isEs
          ? 'Rendimiento'
          : 'Performance';
  String get startupPage => _isDe
      ? 'Startseite'
      : _isEs
          ? 'Página de inicio'
          : 'Startup page';
  String get bgPreloadLabel => _isDe
      ? 'Hintergrund: Listen vorladen (schont Server, lädt ohne Karten)'
      : _isEs
          ? 'Segundo plano: precargar columnas (ahorra servidor, sin tarjetas)'
          : 'Background: preload columns (saves server, no cards)';
  String get bgPreloadShort => _isDe
      ? 'Listen vorladen'
      : _isEs
          ? 'Precargar columnas'
          : 'Preload columns';
  String get bgPreloadHelp => _isDe
      ? 'Lädt im Hintergrund nur die Listen (Stacks) aller Boards in den Cache. Karten werden weiterhin nur bei Bedarf geladen.'
      : _isEs
          ? 'Carga en segundo plano solo las columnas (stacks) de todos los tableros en caché. Las tarjetas se cargan bajo demanda.'
          : 'Preloads only columns (stacks) of all boards into cache. Cards still load on demand.';
  String get bgPreloadHelpShort => _isDe
      ? 'Hintergrund: nur Listen laden.'
      : _isEs
          ? 'Segundo plano: solo columnas.'
          : 'Background: columns only.';
  String get fullSyncManualHint => _isDe
      ? 'Hinweis: Die vollständige Synchronisation aller Boards läuft nur manuell über „Anstehend“ → Aktualisieren. Für normales Arbeiten wird nichts automatisch gestartet.'
      : _isEs
          ? 'Aviso: La sincronización completa de todos los tableros solo se ejecuta manualmente desde “Próximas” → Actualizar. No se inicia automáticamente durante el trabajo normal.'
          : 'Note: Full sync across all boards runs only when manually triggered from “Upcoming” → Refresh. Nothing runs automatically during normal work.';
  String get upcomingProgressHelp => _isDe
      ? 'Hinweis zu „Anstehende Karten“: Die Anzeige neben dem Titel (z. B. 4 / 12) zeigt den Fortschritt eines Hintergrund-Scans über alle Boards. Mit langem Druck auf den Aktualisieren-Button wird ein vollständiger Scan gestartet.'
      : _isEs
          ? 'Nota sobre “Próximas”: La indicación junto al título (p. ej. 4 / 12) muestra el progreso de un escaneo en segundo plano por todos los tableros. Una pulsación larga en actualizar inicia un escaneo completo.'
          : 'Note on “Upcoming”: The indicator next to the title (e.g., 4 / 12) shows background scan progress across all boards. Long-press refresh to run a full scan.';
  String get clearLocalData => _isDe
      ? 'Lokale Daten löschen'
      : _isEs
          ? 'Borrar datos locales'
          : 'Clear local data';
  String get clearLocalDataHelp => _isDe
      ? 'Entfernt zwischengespeicherte Boards und Karten und startet eine neue Synchronisierung.'
      : _isEs
          ? 'Elimina los tableros y tarjetas en caché y realiza una sincronización nueva.'
          : 'Removes cached boards and cards and triggers a fresh sync.';
  String get clearLocalDataConfirmTitle => _isDe
      ? 'Lokale Daten wirklich löschen?'
      : _isEs
          ? '¿Borrar datos locales?'
          : 'Clear local data?';
  String get clearLocalDataConfirmMessage => _isDe
      ? 'Alle zwischengespeicherten Boards und Karten werden entfernt. Deine Anmeldung bleibt erhalten.'
      : _isEs
          ? 'Se eliminarán los tableros y tarjetas en caché. Tu inicio de sesión permanece guardado.'
          : 'Cached boards and cards will be removed. Your login stays saved.';
  String get clearLocalDataConfirmAction => _isDe
      ? 'Löschen'
      : _isEs
          ? 'Borrar'
          : 'Clear';
  String get helpContact => _isDe
      ? 'Bei Fragen, Problemen oder eigenen Projektideen jederzeit Mail an holger@heidkamp.dev'
      : _isEs
          ? 'Para preguntas, problemas o ideas de tus propios proyectos, envía un correo a holger@heidkamp.dev'
          : 'For questions, problems or your own project ideas, feel free to email holger@heidkamp.dev';
  String get help => _isDe
      ? 'Hilfe'
      : _isEs
          ? 'Ayuda'
          : 'Help';
  String get helpQuickStartTitle => _isDe
      ? 'Schnellstart'
      : _isEs
          ? 'Inicio rapido'
          : 'Quick start';
  String get helpQuickStartBody => _isDe
      ? 'Serveradresse, Benutzername und App-Passwort eingeben und auf "Login & Boards laden" tippen. Die Boards werden aus Nextcloud Deck geladen.'
      : _isEs
          ? 'Introduce servidor, usuario y contrasena de app y toca "Iniciar sesion y cargar tableros". Los tableros se cargan desde Nextcloud Deck.'
          : 'Enter server, username, and app password, then tap "Login & load boards". Boards are loaded from Nextcloud Deck.';
  String get helpTipsTitle => _isDe
      ? 'Tipps'
      : _isEs
          ? 'Consejos'
          : 'Tips';
  String get helpTipsBody => _isDe
      ? 'Im Board kannst du Listen und Aktionen ueber das Burger-Menue verwalten. Benachrichtigungen findest du weiter unten in den Einstellungen.'
      : _isEs
          ? 'En el tablero puedes gestionar listas y acciones desde el menu hamburguesa. Las notificaciones estan mas abajo en ajustes.'
          : 'In boards you can manage lists and actions from the burger menu. Notifications are further down in settings.';
  String get upcomingSingleColumnLabel => _isDe
      ? 'Anstehend einspaltig anzeigen'
      : _isEs
          ? 'Mostrar Próximas en una sola columna'
          : 'Show Upcoming as single column';
  String get upcomingSingleColumnHelp => _isDe
      ? 'Zeigt alle Karten untereinander, getrennt nach Abschnitten (Überfällig, Heute, Morgen, Nächste 7 Tage, Später).'
      : _isEs
          ? 'Muestra todas las tarjetas de arriba a abajo por secciones (Vencidas, Hoy, Mañana, Próximos 7 días, Más tarde).'
          : 'Shows all cards top-to-bottom by sections (Overdue, Today, Tomorrow, Next 7 days, Later).';
  String get showOnlyMyCardsLabel => _isDe
      ? 'Immer nur meine Karten anzeigen'
      : _isEs
          ? 'Mostrar solo mis tarjetas'
          : 'Always show only my cards';
  String get showOnlyMyCardsHelp => _isDe
      ? 'Filtert Anstehend und Boards auf Karten, die dir zugewiesen sind.'
      : _isEs
          ? 'Filtra Próximas y tableros a las tarjetas asignadas a ti.'
          : 'Filters Upcoming and boards to cards assigned to you.';
  String get cacheBoardsLocalLabel => _isDe
      ? 'Boards lokal speichern (schnelles Wiederöffnen, nur geänderte Boards prüfen)'
      : _isEs
          ? 'Guardar tableros localmente (apertura rápida, solo comprobar tableros cambiados)'
          : 'Store boards locally (fast reopen, only check changed boards)';
  String get cacheBoardsLocalShort => _isDe
      ? 'Boards lokal speichern'
      : _isEs
          ? 'Guardar tableros localmente'
          : 'Store boards locally';
  String get cacheBoardsLocalHelp => _isDe
      ? 'Speichert Boards lokal und nutzt ETags, um beim Start nur geänderte Boards neu zu prüfen. Deaktivieren, wenn dein Server keine ETags liefert.'
      : _isEs
          ? 'Guarda los tableros localmente y usa ETags para comprobar solo los tableros cambiados al iniciar. Desactívalo si tu servidor no proporciona ETags.'
          : 'Stores boards locally and uses ETags to check only changed boards on launch. Disable if your server does not provide ETags.';
  String get cacheBoardsLocalHelpShort => _isDe
      ? 'Nur geänderte Boards prüfen (ETag).'
      : _isEs
          ? 'Solo tableros cambiados (ETag).'
          : 'Only changed boards (ETag).';
  // Overview – cache indicator
  String get cacheLabel => _isDe
      ? 'Cache'
      : _isEs
          ? 'Caché'
          : 'Cache';
  // Language
  String get language => _isDe
      ? 'Sprache'
      : _isEs
          ? 'Idioma'
          : 'Language';
  String get supportAndData => _isDe
      ? 'Support & Daten'
      : _isEs
          ? 'Soporte y datos'
          : 'Support & Data';
  String get systemLanguage => _isDe
      ? 'System'
      : _isEs
          ? 'Sistema'
          : 'System';
  String get german => _isDe
      ? 'Deutsch'
      : _isEs
          ? 'Alemán'
          : 'German';
  String get english => _isDe
      ? 'Englisch'
      : _isEs
          ? 'Inglés'
          : 'English';
  String get spanish => _isDe
      ? 'Spanisch'
      : _isEs
          ? 'Español'
          : 'Spanish';
  // Security / Network
  String get httpsEnforcedInfo => _isDe
      ? 'Next Deck nutzt immer HTTPS. Kein Protokoll (http/https) eingeben.'
      : _isEs
          ? 'Next Deck usa siempre HTTPS. No introduzcas protocolo (http/https).'
          : 'Next Deck always uses HTTPS. Do not enter a protocol (http/https).';
  // Navigation
  String get navUpcoming => _isDe
      ? 'Anstehend'
      : _isEs
          ? 'Próximas'
          : 'Upcoming';
  String get upcomingTitle => _isDe
      ? 'Anstehende Karten'
      : _isEs
          ? 'Tarjetas próximas'
          : 'Upcoming cards';
  String get noDueCards => _isDe
      ? 'Keine fälligen Karten'
      : _isEs
          ? 'No hay tarjetas con vencimiento'
          : 'No due cards';
  String get navBoard => _isDe
      ? 'Board'
      : _isEs
          ? 'Tablero'
          : 'Board';
  // Upcoming sections
  String get today => _isDe
      ? 'Heute'
      : _isEs
          ? 'Hoy'
          : 'Today';
  String get tomorrow => _isDe
      ? 'Morgen'
      : _isEs
          ? 'Mañana'
          : 'Tomorrow';
  String get next7Days => _isDe
      ? 'Nächste 7 Tage'
      : _isEs
          ? 'Próximos 7 días'
          : 'Next 7 days';
  String get later => _isDe
      ? 'Später'
      : _isEs
          ? 'Más tarde'
          : 'Later';
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
