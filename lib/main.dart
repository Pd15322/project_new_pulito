import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'package:esc_pos_printer/esc_pos_printer.dart';
import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'package:ping_discover_network_forked/ping_discover_network_forked.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'screens/auth_check.dart';
import 'screens/login_screen.dart';
import 'screens/gestione_dipendenti.dart';
import 'cestino_manager.dart';
import 'screens/cestino_screen.dart';
import 'dart:async';

bool firebaseInitialized = false;

// NUOVO: Sistema di gestione stampanti migliorato

enum PrinterStatus {
  disconnected,
  connecting,
  connected,
  error
}

class ManagedPrinter {
  String id;
  String name;
  String? ipAddress;
  int port;
  PrinterStatus status;
  NetworkPrinter? printer;
  String? errorMessage;
  DateTime? lastConnected;

  ManagedPrinter({
    required this.id,
    required this.name,
    this.ipAddress,
    this.port = 9100,
    this.status = PrinterStatus.disconnected,
  });

  // Connetti stampante
  Future<bool> connect() async {
    if (ipAddress == null) return false;

    status = PrinterStatus.connecting;

    try {
      final profile = await CapabilityProfile.load();
      printer = NetworkPrinter(PaperSize.mm80, profile);

      final res = await printer!.connect(
          ipAddress!,
          port: port,
          timeout: Duration(seconds: 10)
      );

      if (res == PosPrintResult.success) {
        status = PrinterStatus.connected;
        lastConnected = DateTime.now();
        errorMessage = null;
        return true;
      } else {
        status = PrinterStatus.error;
        errorMessage = res.msg;
        return false;
      }
    } catch (e) {
      status = PrinterStatus.error;
      errorMessage = e.toString();
      return false;
    }
  }

  // Disconnetti stampante
  void disconnect() {
    try {
      printer?.disconnect();
    } catch (e) {
      print('Errore disconnessione: $e');
    }
    printer = null;
    status = PrinterStatus.disconnected;
    errorMessage = null;
  }

  // Verifica se è connessa
  bool get isConnected => status == PrinterStatus.connected && printer != null;
}

// Service per gestire tutte le stampanti
class PrinterService {
  static final PrinterService _instance = PrinterService._internal();

  factory PrinterService() => _instance;

  PrinterService._internal();

  final Map<String, ManagedPrinter> _printers = {};
  Timer? _reconnectTimer;

  // Inizializza le stampanti
  void initializePrinters() {
    _printers['cucina'] = ManagedPrinter(id: 'cucina', name: 'CUCINA');
    _printers['cassa'] = ManagedPrinter(id: 'cassa', name: 'CASSA');

    // Carica configurazioni salvate
    _loadSavedConfigurations();

    // Avvia timer per riconnessione automatica
    _startReconnectTimer();
  }

  // Ottieni stampante per ID
  ManagedPrinter? getPrinter(String id) => _printers[id];

  // Ottieni tutte le stampanti
  List<ManagedPrinter> getAllPrinters() => _printers.values.toList();

  // Connetti tutte le stampanti configurate
  Future<void> connectAllConfiguredPrinters() async {
    for (var printer in _printers.values) {
      if (printer.ipAddress != null && !printer.isConnected) {
        await printer.connect();
      }
    }
  }

  // Timer per riconnessione automatica
  void _startReconnectTimer() {
    _reconnectTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      _attemptReconnections();
    });
  }

  // Riconnetti stampanti disconnesse
  Future<void> _attemptReconnections() async {
    for (var printer in _printers.values) {
      if (printer.ipAddress != null &&
          printer.status == PrinterStatus.disconnected) {
        await printer.connect();
      }
    }
  }

  // Carica configurazioni salvate
  Future<void> _loadSavedConfigurations() async {
    final prefs = await SharedPreferences.getInstance();

    for (var printer in _printers.values) {
      final ip = prefs.getString('printer_${printer.id}_ip');
      final port = prefs.getInt('printer_${printer.id}_port') ?? 9100;

      if (ip != null) {
        printer.ipAddress = ip;
        printer.port = port;
      }
    }
  }

  // Salva configurazione stampante
  Future<void> savePrinterConfig(String printerId, String ip, int port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('printer_${printerId}_ip', ip);
    await prefs.setInt('printer_${printerId}_port', port);

    final printer = _printers[printerId];
    if (printer != null) {
      printer.ipAddress = ip;
      printer.port = port;
    }
  }

  void dispose() {
    _reconnectTimer?.cancel();
    for (var printer in _printers.values) {
      printer.disconnect();
    }
  }
}

// Istanza globale del service
final printerService = PrinterService();

// NUOVO: Mappa dei prezzi
Map<String, double> prezziMenu = {
  // SERVIZIO
  'COPERTO': 3.0,

  // ANTIPASTI
  'FREDDI': 12.0,
  'CALDI': 18.0,
  'CALDI TOP': 28.0,
  'INSALATA DI MARE': 10.0,
  'D&G': 12.0,
  'IMPEPATA': 13.0,
  'SAUTÈ': 13.0,
  'OSTRICHE': 3.50,
  'CRUDI': 24.0,
  'GRAN PLATEAU DI CRUDI': 73.0,

  // PRIMI
  'CHITARRA VONGOLE': 10.0,
  'GNOCCHI SCOGLIO': 15.0,
  'PRIMO NOSTRO': 16.0,
  'RISOTTO': 16.0,
  'SPAGHETTI GLUTEN FREE': 14.0,

  // SECONDI
  'FRITTURA SS': 14.0,
  'FRITTURA MISTA': 15.0,
  'FRITTURA SOLO CALAMARI': 14.0,
  'GRIGLIATA MISTA': 25.0,
  'SPIEDINO GRIGLIATO': 2.5,
  'ORATA CON PATATE': 23.0,
  'SPIGOLA CON PATATE': 22.0,

  // CONTORNI
  'PATATINE FRITTE': 4.0,
  'VERDURA GRIGLIATA': 5.0,
  'INSALATA MISTA': 4.0,

  // ALTRO
  'PASTA CON POMODORO': 6.0,
  'COTOLETTA E PATATINE': 10.0,

  // BEVANDE
  'ACQUA NAT': 2.0,
  'ACQUA FRIZZ': 2.0,
  'COCALITRO': 6.0,
  'PERONI': 3.0,
  'BIANCA PIPERITA': 6.0,
  'LATTINA': 3.0,

  // VINI DELLA CASA
  'BIANCO - 0.75': 11.0,
  'BIANCO - 0.50': 8.0,
  'BIANCO - 0.25': 5.0,
  'ROSATO - 0.75': 11.0,
  'ROSATO - 0.50': 8.0,
  'ROSATO - 0.25': 5.0,
  'CALICE': 5.0,

  // VINI BIANCHI E ROSATI
  'PECORINO AGRIVERDE': 19.0,
  'PECORINO SUPERIORE': 26.0,
  'GEWURZTRAMINER': 29.0,
  'PASSERINA SPUMANTIZZATA': 22.0,
  'ROSATO TESTAROSSA': 24.0,
  'PASSERINA TESTAROSSA': 23.0,
  'TREBBIANO FONTECUPA': 23.0,
  'CERASUOLO FONTECUPA': 24.0,
  'COCOCCIOLA': 24.0,
  'CERASUOLO STRAPPELLI': 24.0,
  'VILLAGEMMA': 28.0,
  'MONTEPULCIANO ROSSO': 20.0,
  'PROSECCO': 20.0,
  'FERGHETTINA BIANCO': 65.0,
  'FERGHETTINA ROSATO': 65.0,
  'CÀ DEL BOSCO': 65.0,
  'JIN TONIC LONDON': 7.0,
  'JIN TONIC HENDRICKS': 10.0,

  // DOLCI
  'SORBETTO': 3.0,
  'TIRAMISÙ': 5.0,
  'CHEESECAKE PISTACCHIO': 5.0,
  'CHEESECAKE NUTELLA': 5.0,
  'CHEESECAKE FRUTTI DI BOSCO': 5.0,

  // BAR
  'CAFFÈ ESPRESSO': 1.30,
  'CAFFÈ MACCHIATO': 1.50,
  'CAFFÈ CORRETTO': 1.50,
  'CAPPUCCINO': 2.50,
  'AMARO': 3.0,
  'RUM': 6.0,
};

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Mantieni lo schermo sempre acceso
  WakelockPlus.enable();

  // Inizializza il sistema stampanti
  printerService.initializePrinters();

  // INIZIALIZZAZIONE FIREBASE FORZATA - DEVE SEMPRE FUNZIONARE
  try {
    print('🔥 Inizializzazione Firebase FORZATA...');

    // Gestione più robusta del duplicate-app
    FirebaseApp? app;
    try {
      app = Firebase.app(); // Controlla se esiste già
      print('✅ Firebase già presente: ${app.name}');
    } catch (e) {
      // Non esiste, inizializzalo
      app = await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      print('✅ Firebase inizializzato da zero: ${app.name}');
    }

    firebaseInitialized = true;
    print('🎯 Firebase status: ATTIVO');

    // Carica prezzi
    await _loadPrezziDaFirebase();
    await _puliziaFuoriMenu();
  } catch (e) {
    // Se è duplicate app, consideralo successo
    if (e.toString().contains('duplicate-app')) {
      print('✅ Firebase duplicate-app risolto - continuiamo');
      firebaseInitialized = true;
      await _loadPrezziDaFirebase();
    } else {
      // ERRORE REALE = APP NON PARTE
      print('🚨 ERRORE CRITICO FIREBASE: $e');

      // Mostra errore critico e blocca app
      runApp(MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.red,
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error, size: 100, color: Colors.white),
                SizedBox(height: 20),
                Text(
                  'ERRORE FIREBASE',
                  style: TextStyle(color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 10),
                Text(
                  'L\'app non può funzionare\nsenza connessione Firebase',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                SizedBox(height: 20),
                Text(
                  'Errore: $e',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ));
      return; // BLOCCA QUI
    }
  }

  // Connetti automaticamente le stampanti all'avvio
  await printerService.connectAllConfiguredPrinters();

  runApp(MyApp());
}

// MODIFICATO: Funzione per caricare i prezzi da Firebase
Future<void> _loadPrezziDaFirebase() async {
  if (!firebaseInitialized) return;

  try {
    final doc = await FirebaseFirestore.instance
        .collection('impostazioni')
        .doc('prezzi')
        .get();

    if (doc.exists) {
      Map<String, dynamic> prezziFirebase = doc.data() ?? {};

      // Carica TUTTI i prezzi da Firebase (inclusi i fuori menù temporanei)
      prezziFirebase.forEach((piatto, valore) {
        // MODIFICA QUI: Gestisci il nuovo formato con timestamp
        if (piatto.startsWith('FM:')) {
          // Se è un oggetto con timestamp
          if (valore is Map && valore['prezzo'] != null) {
            prezziMenu[piatto] = (valore['prezzo'] as num).toDouble();
            print(
                '📥 Fuori menù caricato all\'avvio: $piatto = €${valore['prezzo']}');
          } else {
            // Vecchio formato (solo numero)
            prezziMenu[piatto] = (valore as num).toDouble();
            print(
                '📥 Fuori menù (vecchio formato) caricato: $piatto = €$valore');
          }
        } else {
          // Piatti normali
          prezziMenu[piatto] = (valore as num).toDouble();
        }
      });

      print('✅ Prezzi caricati da Firebase');
      print('📊 Totale prezzi in memoria: ${prezziMenu.length}');
      print('📊 Di cui fuori menù: ${prezziMenu.keys
          .where((k) => k.startsWith("FM:"))
          .length}');
    } else {
      // Se non esistono prezzi su Firebase, salva quelli di default
      await _salvaPrezziSuFirebase();
      print('📤 Prezzi di default salvati su Firebase');
    }
  } catch (e) {
    print('❌ Errore caricamento prezzi da Firebase: $e');
  }
}

// NUOVO: Funzione per salvare i prezzi su Firebase
Future<void> _salvaPrezziSuFirebase() async {
  if (!firebaseInitialized) return;

  try {
    await FirebaseFirestore.instance
        .collection('impostazioni')
        .doc('prezzi')
        .set(prezziMenu);

    print('✅ Prezzi salvati su Firebase');
  } catch (e) {
    print('❌ Errore salvataggio prezzi su Firebase: $e');
  }
}

// NUOVO
Future<void> _puliziaFuoriMenu() async {
  if (!firebaseInitialized) return;

  try {
    final doc = await FirebaseFirestore.instance
        .collection('impostazioni')
        .doc('prezzi')
        .get();

    if (doc.exists) {
      Map<String, dynamic> prezziFirebase = doc.data() ?? {};
      Map<String, dynamic> prezziPuliti = {};
      final now = DateTime.now();

      prezziFirebase.forEach((chiave, valore) {
        if (chiave.startsWith('FM:')) {
          // Cerca il timestamp associato
          String timestampKey = '${chiave}_timestamp';
          if (prezziFirebase.containsKey(timestampKey)) {
            final timestamp = DateTime.parse(prezziFirebase[timestampKey]);
            final differenza = now
                .difference(timestamp)
                .inHours;

            if (differenza < 4) {
              prezziPuliti[chiave] = valore;
              prezziPuliti[timestampKey] = prezziFirebase[timestampKey];
            } else {
              print('🗑️ Eliminato fuori menù vecchio: $chiave');
            }
          } else {
            // Vecchio formato senza timestamp, mantieni
            prezziPuliti[chiave] = valore;
          }
        } else if (!chiave.endsWith('_timestamp')) {
          // Piatti normali (escludi i timestamp)
          prezziPuliti[chiave] = valore;
        }
      });

      // Aggiorna Firebase
      await FirebaseFirestore.instance
          .collection('impostazioni')
          .doc('prezzi')
          .set(prezziPuliti);

      print('✅ Pulizia fuori menù completata');
    }
  } catch (e) {
    print('❌ Errore pulizia fuori menù: $e');
  }
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'App Ristorante',
      theme: ThemeData.dark(),
      home: AuthCheck(),
    );
  }
}

class SchermataTavoli extends StatefulWidget {
  final String username;

  SchermataTavoli({required this.username});

  @override
  _SchermataTavoliState createState() => _SchermataTavoliState();
}

class _SchermataTavoliState extends State<SchermataTavoli> {
  Map<int, bool> _tavoliOccupati = {};
  bool _isAdmin = false;
  StreamSubscription? _ordiniListener;

  @override
  void initState() {
    super.initState();
    _checkAdminStatus();
    _loadTavoliOccupati();
  }

  Future<void> _checkAdminStatus() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isAdmin = prefs.getBool('isAdmin') ?? false;
    });
  }

  // NUOVO: Libera tutti i tavoli attivi
  Future<void> _liberaTuttiITavoli() async {
    // Conta quanti tavoli sono occupati
    int tavoliOccupati = _tavoliOccupati.values
        .where((occupato) => occupato == true)
        .length;

    if (tavoliOccupati == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nessun tavolo da liberare'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Dialog di conferma
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) =>
          AlertDialog(
            title: Text('⚠️ ATTENZIONE'),
            content: Text(
                'Vuoi liberare TUTTI i $tavoliOccupati tavoli occupati?\n\nGli ordini saranno salvati nel cestino.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('Annulla'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text('LIBERA TUTTI', style: TextStyle(
                    color: Colors.red, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
    );

    if (confirm == true) {
      // Nascondi eventuali messaggi precedenti
      ScaffoldMessenger.of(context).clearSnackBars();

      // Libera tutti i tavoli occupati
      List<int> tavoliDaLiberare = [];
      _tavoliOccupati.forEach((tavolo, occupato) {
        if (occupato == true) {
          tavoliDaLiberare.add(tavolo);
        }
      });

      // Libera i tavoli uno per uno (nascondendo i messaggi intermedi)
      for (int tavoloNumero in tavoliDaLiberare) {
        await _liberaTavoloCompleto(tavoloNumero);
        // Nascondi subito il messaggio del singolo tavolo
        ScaffoldMessenger.of(context).clearSnackBars();
      }

      // Mostra UN SOLO messaggio finale
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${tavoliDaLiberare
              .length} tavoli liberati e salvati nel cestino'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  // Carica lo stato dei tavoli da Firebase con listener real-time
  void _loadTavoliOccupati() {
    if (!firebaseInitialized) return;

    try {
      // Listener real-time per aggiornamenti istantanei
      _ordiniListener = FirebaseFirestore.instance
          .collection('ordini')
          .where('status', isEqualTo: 'active')
          .snapshots()
          .listen((snapshot) {
        print(
            '🔥 AGGIORNAMENTO REAL-TIME: ${snapshot.docs.length} ordini attivi');
        print('🔥 Dispositivo: ${DateTime.now()}');

        // Debug per ogni ordine
        for (var doc in snapshot.docs) {
          print('🔥 Ordine: Tavolo ${doc.data()['tavoloNumero']} - Status: ${doc
              .data()['status']}');
        }

        Map<int, bool> nuoviTavoliOccupati = {};
        for (var doc in snapshot.docs) {
          int tavoloNumero = doc.data()['tavoloNumero'];
          nuoviTavoliOccupati[tavoloNumero] = true;

          // DEBUG SPECIFICO PER TAVOLO 1
          if (tavoloNumero == 1) {
            print('🔍 TAVOLO 1 TROVATO IN FIREBASE - Ordine ID: ${doc.id}');
            print('🔍 Status ordine: ${doc.data()['status']}');
          }
        }

        print(
            '🔥 TAVOLI OCCUPATI CALCOLATI: $nuoviTavoliOccupati'); // NUOVO DEBUG

        if (mounted) {
          setState(() {
            _tavoliOccupati = nuoviTavoliOccupati;
          });
          print('🔥 STATO TAVOLI AGGIORNATO: $_tavoliOccupati'); // NUOVO DEBUG
        }
      });
    } catch (e) {
      print('Errore listener tavoli: $e');
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) =>
          AlertDialog(
            title: Text('Disconnetti'),
            content: Text('Vuoi davvero disconnetterti?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('Annulla'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text('Disconnetti', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
    );

    if (confirm == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => LoginScreen()),
      );
    }
  }

  void _setTavoloOccupato(int tavoloNumero, bool occupato) {
    setState(() {
      _tavoliOccupati[tavoloNumero] = occupato;
    });
  }

  Color _getColoreTavolo(int tavoloNumero) {
    return _tavoliOccupati.containsKey(tavoloNumero) &&
        _tavoliOccupati[tavoloNumero]!
        ? Colors.red
        : Colors.green;
  }

  void _vaiASchermataCoperti(int tavoloNumero, BuildContext context) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SchermataCoperti(tavoloNumero: tavoloNumero),
      ),
    );

    if (result == true) {
      _setTavoloOccupato(tavoloNumero, true);
    }
  }

  // Vai direttamente al menù per tavolo occupato
  void _vaiASchermataMenuEsistente(int tavoloNumero,
      BuildContext context) async {
    // Recupera gli ordini esistenti per questo tavolo
    List<OrderItem> ordiniEsistenti = [];
    int numeroCoperti = 1;

    if (firebaseInitialized) {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('ordini')
            .where('tavoloNumero', isEqualTo: tavoloNumero)
            .where('status', isEqualTo: 'active')
            .get();

        if (snapshot.docs.isNotEmpty) {
          var ultimoOrdine = snapshot.docs.first.data();
          numeroCoperti = ultimoOrdine['numeroCoperti'] ?? 1;

          List<dynamic> items = ultimoOrdine['items'] ?? [];
          ordiniEsistenti = items.map((item) =>
              OrderItem(
                name: item['name'],
                quantity: item['quantity'] ?? 0,
                note: item['note'] ?? '',
                isSeparator: item['isSeparator'] ?? false,
              )).toList();
          print('📥 CARICAMENTO ORDINE ESISTENTE:');
          print('Ordini caricati: ${ordiniEsistenti.map((e) => '${e.name}x${e
              .quantity}').join(', ')}');
        }
      } catch (e) {
        print('Errore caricamento ordine esistente: $e');
      }
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            SchermataMenu(
              tavoloNumero: tavoloNumero,
              numeroCoperti: numeroCoperti,
              ordiniEsistenti: ordiniEsistenti,
            ),
      ),
    );

    // Ricarica lo stato dei tavoli quando si torna
    _loadTavoliOccupati();
  }

  // Modifica numero coperti di un tavolo occupato
  Future<void> _modificaCopertiTavolo(int tavoloNumero) async {
    if (!firebaseInitialized) return;

    try {
      // Recupera l'ordine esistente
      final snapshot = await FirebaseFirestore.instance
          .collection('ordini')
          .where('tavoloNumero', isEqualTo: tavoloNumero)
          .where('status', isEqualTo: 'active')
          .get();

      if (snapshot.docs.isEmpty) return;

      final ordineDoc = snapshot.docs.first;
      final ordineData = ordineDoc.data();
      final copertiAttuali = ordineData['numeroCoperti'] ?? 1;

      // Mostra dialog per modificare
      final nuoviCoperti = await showDialog<int>(
        context: context,
        builder: (context) => _DialogModificaCoperti(
          tavoloNumero: tavoloNumero,
          copertiAttuali: copertiAttuali,
        ),
      );

      if (nuoviCoperti != null && nuoviCoperti != copertiAttuali) {
        // Aggiorna su Firebase
        await FirebaseFirestore.instance
            .collection('ordini')
            .doc(ordineDoc.id)
            .update({
          'numeroCoperti': nuoviCoperti,
          'lastUpdate': FieldValue.serverTimestamp(),
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Coperti Tavolo $tavoloNumero aggiornati: $nuoviCoperti'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Errore modifica coperti: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore modifica coperti'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // NUOVA FUNZIONE: Libera tavolo e cancella ordine da Firebase
  Future<void> _liberaTavoloCompleto(int tavoloNumero) async {
    print('🗑️ Liberando tavolo $tavoloNumero completamente...');

    // DEBUG SPECIFICO PER TAVOLO 1
    if (tavoloNumero == 1) {
      print('🔍 DEBUG TAVOLO 1 - Stato prima: ${_tavoliOccupati[1]}');
    }

    // Prima di liberare, salva l'ordine nel cestino
    if (firebaseInitialized) {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('ordini')
            .where('tavoloNumero', isEqualTo: tavoloNumero)
            .where('status', isEqualTo: 'active')
            .get();

        if (snapshot.docs.isNotEmpty) {
          var ordineDoc = snapshot.docs.first;
          var ordineData = ordineDoc.data();

          // Calcola totale ordine
          double totale = 0.0;
          List<dynamic> items = ordineData['items'] ?? [];
          for (var item in items) {
            if (!item['isSeparator']) {
              double prezzo = prezziMenu[item['name']] ?? 0.0;
              totale += prezzo * (item['quantity'] ?? 0);
            }
          }

          // Aggiungi coperti al totale
          int numeroCoperti = ordineData['numeroCoperti'] ?? 1;
          totale += (prezziMenu['COPERTO'] ?? 3.0) * numeroCoperti;

          // Salva nel cestino
          await CestinoManager().aggiungiAlCestino(
            ordineId: ordineDoc.id,
            tavoloNumero: tavoloNumero,
            numeroCoperti: numeroCoperti,
            items: List<Map<String, dynamic>>.from(items),
            totale: totale,
          );
        }
      } catch (e) {
        print('❌ Errore salvataggio in cestino: $e');
      }
    }

    print('✅ ORDINE SALVATO NEL CESTINO - Tavolo $tavoloNumero');

// Verifica subito
    final ordiniNelCestino = await CestinoManager().contaOrdini();
    print('📊 Totale ordini nel cestino: $ordiniNelCestino');

    // Libera il tavolo localmente
    setState(() {
      _tavoliOccupati[tavoloNumero] = false;
    });

    // DEBUG SPECIFICO PER TAVOLO 1
    if (tavoloNumero == 1) {
      print('🔍 DEBUG TAVOLO 1 - Stato dopo setState: ${_tavoliOccupati[1]}');
    }

    // Se Firebase è disponibile, cancella l'ordine
    if (firebaseInitialized) {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('ordini')
            .where('tavoloNumero', isEqualTo: tavoloNumero)
            .where('status', isEqualTo: 'active')
            .get();

        // Chiudi tutti gli ordini attivi per questo tavolo
        for (var doc in snapshot.docs) {
          await FirebaseFirestore.instance
              .collection('ordini')
              .doc(doc.id)
              .update({
            'status': 'completed',
            'completedAt': FieldValue.serverTimestamp(),
          });
        }

        print('✅ Ordini chiusi su Firebase per tavolo $tavoloNumero');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Tavolo $tavoloNumero liberato (salvato nel cestino)'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        print('❌ Errore liberazione tavolo: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Tavolo liberato localmente (errore Firebase)'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  // Funzione per aprire le impostazioni della stampante
  void _apriImpostazioniStampante() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ImpostazioniStampanteWiFi(),
      ),
    );
  }

  // NUOVO: Funzione per aprire la schermata modifica prezzi
  void _apriModificaPrezzi() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ModificaPrezziScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Container(
          padding: EdgeInsets.all(12.0),
          color: Colors.red,
          child: Center(
            child: Text(
              'SAPORI DI MARE ${firebaseInitialized ? "🔥" : "📴"}',
              style: TextStyle(fontSize: 28,
                  color: Colors.white,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: Container(
        color: Colors.white,
      ),
    );
  }
}

// NUOVO: Schermata per modificare i prezzi
class ModificaPrezziScreen extends StatefulWidget {
  @override
  _ModificaPrezziScreenState createState() => _ModificaPrezziScreenState();
}

class _ModificaPrezziScreenState extends State<ModificaPrezziScreen> {
  Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    // Inizializza i controller per ogni piatto
    prezziMenu.forEach((piatto, prezzo) {
      _controllers[piatto] =
          TextEditingController(text: prezzo.toStringAsFixed(2));
    });

    // Ascolta i cambiamenti dei prezzi su Firebase in tempo reale
    if (firebaseInitialized) {
      FirebaseFirestore.instance
          .collection('impostazioni')
          .doc('prezzi')
          .snapshots()
          .listen((snapshot) {
        if (snapshot.exists) {
          Map<String, dynamic> prezziFirebase = snapshot.data() ?? {};

          setState(() {
            prezziFirebase.forEach((piatto, prezzo) {
              if (prezziMenu.containsKey(piatto)) {
                prezziMenu[piatto] = (prezzo as num).toDouble();
                _controllers[piatto]?.text =
                    prezziMenu[piatto]!.toStringAsFixed(2);
              }
            });
          });
        }
      });
    }
  }

  @override
  void dispose() {
    // Pulisci i controller
    _controllers.forEach((_, controller) => controller.dispose());
    super.dispose();
  }

  Future<void> _salvaPrezzi() async {
    // Aggiorna la mappa prezziMenu con i nuovi valori
    _controllers.forEach((piatto, controller) {
      double? nuovoPrezzo = double.tryParse(controller.text);
      if (nuovoPrezzo != null) {
        prezziMenu[piatto] = nuovoPrezzo;
      }
    });

    if (firebaseInitialized) {
      try {
        // Salva su Firebase
        await FirebaseFirestore.instance
            .collection('impostazioni')
            .doc('prezzi')
            .set(prezziMenu);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Prezzi salvati su Firebase! Tutti i dispositivi sono aggiornati.'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore salvataggio su Firebase: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Firebase non disponibile. I prezzi non saranno sincronizzati.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _pulisciFuoriMenu() async {
    final conferma = await showDialog<bool>(
      context: context,
      builder: (context) =>
          AlertDialog(
            title: Text('Pulisci Fuori Menù'),
            content: Text(
                'Rimuovere tutti i fuori menù salvati?\nQuesta azione non può essere annullata.'),
            actions: [
              TextButton(
                child: Text('Annulla'),
                onPressed: () => Navigator.of(context).pop(false),
              ),
              ElevatedButton(
                child: Text(
                    'Rimuovi Tutti', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
    );

    if (conferma == true && firebaseInitialized) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('impostazioni')
            .doc('prezzi')
            .get();

        if (doc.exists) {
          Map<String, dynamic> prezzi = Map.from(doc.data() ?? {});
          int rimossi = 0;

          // Rimuovi tutti i fuori menù
          prezzi.removeWhere((key, value) {
            if (key.startsWith('FM:')) {
              rimossi++;
              return true;
            }
            return false;
          });

          // Salva su Firebase
          await FirebaseFirestore.instance
              .collection('impostazioni')
              .doc('prezzi')
              .set(prezzi);

          // Rimuovi anche localmente
          setState(() {
            prezziMenu.removeWhere((key, value) => key.startsWith('FM:'));
            _controllers.removeWhere((key, value) => key.startsWith('FM:'));
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Rimossi $rimossi fuori menù'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Modifica Prezzi'),
        actions: [
          IconButton(
            icon: Icon(Icons.cleaning_services, color: Colors.orange),
            onPressed: _pulisciFuoriMenu,
            tooltip: 'Pulisci Fuori Menù',
          ),
          IconButton(
            icon: Icon(Icons.save, color: Colors.green),
            onPressed: _salvaPrezzi,
            tooltip: 'Salva Prezzi',
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.all(16.0),
        children: [
          _buildCategoriaPrezzo('ANTIPASTI', [
            'FREDDI', 'CALDI', 'CALDI TOP', 'INSALATA DI MARE', 'D&G',
            'IMPEPATA', 'SAUTÈ', 'OSTRICHE', 'CRUDI', 'GRAN PLATEAU DI CRUDI'
          ]),
          _buildCategoriaPrezzo('PRIMI', [
            'CHITARRA VONGOLE',
            'GNOCCHI SCOGLIO',
            'PRIMO NOSTRO',
            'RISOTTO',
            'SPAGHETTI GLUTEN FREE'
          ]),
          _buildCategoriaPrezzo('SECONDI', [
            'FRITTURA SS',
            'FRITTURA MISTA',
            'FRITTURA SOLO CALAMARI',
            'GRIGLIATA MISTA',
            'SPIEDINO GRIGLIATO',
            'ORATA CON PATATE',
            'SPIGOLA CON PATATE'
          ]),
          _buildCategoriaPrezzo('CONTORNI', [
            'PATATINE FRITTE', 'VERDURA GRIGLIATA', 'INSALATA MISTA'
          ]),
          _buildCategoriaPrezzo('ALTRO', [
            'PASTA CON POMODORO', 'COTOLETTA E PATATINE'
          ]),
          _buildCategoriaPrezzo('BEVANDE', [
            'ACQUA NAT', 'ACQUA FRIZZ', 'COCALITRO', 'PERONI',
            'BIANCA PIPERITA', 'LATTINA'
          ]),
          _buildCategoriaPrezzo('VINI', [
            'BIANCO - 0.75',
            'BIANCO - 0.50',
            'BIANCO - 0.25',
            'ROSATO - 0.75',
            'ROSATO - 0.50',
            'ROSATO - 0.25',
            'CALICE',
            'PECORINO AGRIVERDE',
            'PECORINO SUPERIORE',
            'GEWURZTRAMINER',
            'PASSERINA SPUMANTIZZATA',
            'ROSATO TESTAROSSA',
            'PASSERINA TESTAROSSA',
            'TREBBIANO FONTECUPA',
            'CERASUOLO FONTECUPA',
            'COCOCCIOLA',
            'CERASUOLO STRAPPELLI',
            'VILLAGEMMA',
            'MONTEPULCIANO ROSSO',
            'PROSECCO',
            'FERGHETTINA BIANCO',
            'FERGHETTINA ROSATO',
            'CÀ DEL BOSCO',
            'JIN TONIC LONDON',
            'JIN TONIC HENDRICKS'
          ]),
          _buildCategoriaPrezzo('DOLCI', [
            'SORBETTO', 'TIRAMISÙ', 'CHEESECAKE PISTACCHIO',
            'CHEESECAKE NUTELLA', 'CHEESECAKE FRUTTI DI BOSCO'
          ]),
          _buildCategoriaPrezzo('BAR', [
            'CAFFÈ ESPRESSO',
            'CAFFÈ MACCHIATO',
            'CAFFÈ CORRETTO',
            'CAPPUCCINO',
            'AMARO',
            'RUM'
          ]),
        ],
      ),
    );
  }

  Widget _buildCategoriaPrezzo(String categoria, List<String> piatti) {
    return Card(
      margin: EdgeInsets.only(bottom: 16.0),
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              categoria,
              style: TextStyle(fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange),
            ),
            SizedBox(height: 12),
            ...piatti.map((piatto) =>
                Padding(
                  padding: EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(piatto, style: TextStyle(fontSize: 16)),
                      ),
                      Expanded(
                        flex: 1,
                        child: TextField(
                          controller: _controllers[piatto],
                          keyboardType: TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                            prefixText: '€ ',
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 8.0, vertical: 4.0),
                            border: OutlineInputBorder(),
                          ),
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                )).toList(),
          ],
        ),
      ),
    );
  }
}

// NUOVO: Schermata impostazioni stampanti con gestione persistente
class ImpostazioniStampanteWiFi extends StatefulWidget {
  @override
  _ImpostazioniStampanteWiFiState createState() =>
      _ImpostazioniStampanteWiFiState();
}

class _ImpostazioniStampanteWiFiState extends State<ImpostazioniStampanteWiFi> {
  final Map<String, TextEditingController> _ipControllers = {};
  final Map<String, TextEditingController> _portControllers = {};

  List<String> _dispositiviTrovati = [];
  bool _isScanning = false;
  Timer? _statusUpdateTimer;

  @override
  void initState() {
    super.initState();
    _initializeControllers();

    // Timer per aggiornare lo stato delle stampanti ogni 2 secondi
    _statusUpdateTimer = Timer.periodic(Duration(seconds: 2), (timer) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _statusUpdateTimer?.cancel();
    _ipControllers.values.forEach((controller) => controller.dispose());
    _portControllers.values.forEach((controller) => controller.dispose());
    super.dispose();
  }

  void _initializeControllers() {
    for (var printer in printerService.getAllPrinters()) {
      _ipControllers[printer.id] =
          TextEditingController(text: printer.ipAddress ?? '');
      _portControllers[printer.id] =
          TextEditingController(text: printer.port.toString());
    }
  }

  // Connetti singola stampante
  Future<void> _connectPrinter(String printerId) async {
    final printer = printerService.getPrinter(printerId);
    if (printer == null) return;

    final ip = _ipControllers[printerId]?.text.trim();
    final port = int.tryParse(_portControllers[printerId]?.text ?? '9100') ??
        9100;

    if (ip == null || ip.isEmpty) {
      _showMessage('Inserisci un indirizzo IP valido', Colors.orange);
      return;
    }

    // Salva la configurazione
    await printerService.savePrinterConfig(printerId, ip, port);

    setState(() {});

    // Prova a connettere
    final success = await printer.connect();

    setState(() {});

    if (success) {
      _showMessage('${printer.name} connessa con successo!', Colors.green);
    } else {
      _showMessage(
          'Errore connessione ${printer.name}: ${printer.errorMessage}',
          Colors.red);
    }
  }

  // Disconnetti singola stampante
  void _disconnectPrinter(String printerId) {
    final printer = printerService.getPrinter(printerId);
    if (printer != null) {
      printer.disconnect();
      setState(() {});
      _showMessage('${printer.name} disconnessa', Colors.orange);
    }
  }

  // Test di stampa
  Future<void> _testStampa(String printerId) async {
    final printer = printerService.getPrinter(printerId);
    if (printer == null || !printer.isConnected) {
      _showMessage(
          'Stampante ${printer?.name ?? printerId} non connessa', Colors.red);
      return;
    }

    try {
      printer.printer!.text('TEST STAMPANTE ${printer.name}',
          styles: PosStyles(
            align: PosAlign.center,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
          ),
          linesAfter: 1);

      printer.printer!.text('--------------------------------',
          styles: PosStyles(align: PosAlign.center));

      printer.printer!.text('Stampante configurata correttamente!',
          styles: PosStyles(align: PosAlign.center), linesAfter: 1);

      printer.printer!.text('SAPORI DI MARE',
          styles: PosStyles(
            align: PosAlign.center,
            height: PosTextSize.size1,
            width: PosTextSize.size1,
          ),
          linesAfter: 1);

      printer.printer!.text('IP: ${printer.ipAddress}:${printer.port}',
          styles: PosStyles(align: PosAlign.center), linesAfter: 1);

      printer.printer!.text('--------------------------------',
          styles: PosStyles(align: PosAlign.center));

      printer.printer!.cut();

      _showMessage('Test di stampa ${printer.name} inviato!', Colors.green);
    } catch (e) {
      _showMessage('Errore stampa ${printer.name}: $e', Colors.red);
    }
  }

  // Cerca stampanti nella rete
  Future<void> _cercaStampantiWiFi() async {
    setState(() {
      _isScanning = true;
      _dispositiviTrovati = [];
    });

    try {
      String subnet = '192.168.1';
      _showMessage('Ricerca stampanti su rete $subnet.xxx ...', Colors.blue);

      final stream = NetworkAnalyzer.discover2(
        subnet,
        9100,
        timeout: Duration(milliseconds: 5000),
      );

      await for (NetworkAddress addr in stream) {
        if (addr.exists) {
          setState(() {
            _dispositiviTrovati.add(addr.ip);
          });
        }
      }

      setState(() {
        _isScanning = false;
      });

      if (_dispositiviTrovati.isEmpty) {
        _showMessage('Nessuna stampante trovata. Inserisci IP manualmente.',
            Colors.orange);
      }
    } catch (e) {
      setState(() {
        _isScanning = false;
      });
      _showMessage('Errore ricerca: $e', Colors.red);
    }
  }

  void _showMessage(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  // Ottieni colore per stato stampante
  Color _getStatusColor(PrinterStatus status) {
    switch (status) {
      case PrinterStatus.connected:
        return Colors.green;
      case PrinterStatus.connecting:
        return Colors.yellow;
      case PrinterStatus.error:
        return Colors.red;
      case PrinterStatus.disconnected:
      default:
        return Colors.grey;
    }
  }

  // Ottieni icona per stato stampante
  IconData _getStatusIcon(PrinterStatus status) {
    switch (status) {
      case PrinterStatus.connected:
        return Icons.wifi;
      case PrinterStatus.connecting:
        return Icons.wifi_tethering;
      case PrinterStatus.error:
        return Icons.wifi_off;
      case PrinterStatus.disconnected:
      default:
        return Icons.wifi_off;
    }
  }

  // Ottieni testo per stato stampante
  String _getStatusText(PrinterStatus status) {
    switch (status) {
      case PrinterStatus.connected:
        return 'CONNESSA';
      case PrinterStatus.connecting:
        return 'CONNESSIONE...';
      case PrinterStatus.error:
        return 'ERRORE';
      case PrinterStatus.disconnected:
      default:
        return 'DISCONNESSA';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('🖨️ Gestione Stampanti WiFi'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: () => setState(() {}),
            tooltip: 'Aggiorna stato',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header con stato generale
            Card(
              color: Colors.grey.shade900,
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      '📡 STATO SISTEMA STAMPANTI',
                      style: TextStyle(fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                    SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: printerService.getAllPrinters().map((printer) {
                        return Column(
                          children: [
                            Icon(
                              _getStatusIcon(printer.status),
                              color: _getStatusColor(printer.status),
                              size: 32,
                            ),
                            Text(
                              printer.name,
                              style: TextStyle(
                                  color: Colors.white, fontSize: 12),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 16),

            // Configurazione per ogni stampante
            ...printerService.getAllPrinters().map((printer) =>
                _buildPrinterCard(printer)).toList(),

            SizedBox(height: 16),

            // Pulsante ricerca stampanti
            ElevatedButton.icon(
              onPressed: _isScanning ? null : _cercaStampantiWiFi,
              icon: _isScanning
                  ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
              )
                  : Icon(Icons.search),
              label: Text(_isScanning
                  ? 'Ricerca in corso...'
                  : 'Cerca Stampanti nella Rete'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                padding: EdgeInsets.symmetric(vertical: 16),
                textStyle: TextStyle(fontSize: 18),
              ),
            ),

            // Lista dispositivi trovati
            if (_dispositiviTrovati.isNotEmpty) ...[
              SizedBox(height: 16),
              Text('Stampanti trovate:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Container(
                height: 150,
                child: Card(
                  color: Colors.grey.shade900,
                  child: ListView.builder(
                    itemCount: _dispositiviTrovati.length,
                    itemBuilder: (context, index) {
                      final ip = _dispositiviTrovati[index];
                      return ListTile(
                        title: Text(ip, style: TextStyle(color: Colors.white)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: printerService.getAllPrinters().map((
                              printer) {
                            return Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: ElevatedButton(
                                onPressed: () {
                                  _ipControllers[printer.id]?.text = ip;
                                },
                                child: Text(printer.name),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: printer.id == 'cucina'
                                      ? Colors.orange
                                      : Colors.blue,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPrinterCard(ManagedPrinter printer) {
    final isConnected = printer.isConnected;
    final canConnect = _ipControllers[printer.id]?.text
        .trim()
        .isNotEmpty ?? false;

    return Card(
      color: Colors.grey.shade900,
      margin: EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header con nome e stato
            Row(
              children: [
                Icon(
                  printer.id == 'cucina' ? Icons.restaurant : Icons
                      .point_of_sale,
                  color: printer.id == 'cucina' ? Colors.orange : Colors.blue,
                  size: 28,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'STAMPANTE ${printer.name}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: printer.id == 'cucina' ? Colors.orange : Colors
                          .blue,
                    ),
                  ),
                ),
                // Indicatore stato
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getStatusColor(printer.status),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_getStatusIcon(printer.status), color: Colors.white,
                          size: 16),
                      SizedBox(width: 4),
                      Text(
                        _getStatusText(printer.status),
                        style: TextStyle(color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            SizedBox(height: 12),

            // Campi configurazione
            TextField(
              controller: _ipControllers[printer.id],
              decoration: InputDecoration(
                labelText: 'Indirizzo IP',
                hintText: 'Es: 192.168.1.100',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.network_wifi),
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),

            SizedBox(height: 12),

            TextField(
              controller: _portControllers[printer.id],
              decoration: InputDecoration(
                labelText: 'Porta (default: 9100)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.settings_ethernet),
              ),
              keyboardType: TextInputType.number,
            ),

            // Messaggio errore se presente
            if (printer.errorMessage != null) ...[
              SizedBox(height: 8),
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade800,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Errore: ${printer.errorMessage}',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],

            // Ultima connessione
            if (printer.lastConnected != null) ...[
              SizedBox(height: 8),
              Text(
                'Ultima connessione: ${printer.lastConnected!.hour}:${printer
                    .lastConnected!.minute.toString().padLeft(2, '0')}',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],

            SizedBox(height: 12),

            // Pulsanti azione
            Row(
              children: [
                // Pulsante Connetti/Disconnetti
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isConnected
                        ? () => _disconnectPrinter(printer.id)
                        : canConnect
                        ? () => _connectPrinter(printer.id)
                        : null,
                    icon: Icon(isConnected ? Icons.wifi_off : Icons.wifi),
                    label: Text(isConnected ? 'DISCONNETTI' : 'CONNETTI'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isConnected ? Colors.red : Colors.green,
                      padding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),

                SizedBox(width: 8),

                // Pulsante Test
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isConnected
                        ? () => _testStampa(printer.id)
                        : null,
                    icon: Icon(Icons.print),
                    label: Text('TEST'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: printer.id == 'cucina'
                          ? Colors.orange
                          : Colors.blue,
                      padding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SchermataCoperti extends StatefulWidget {
  final int tavoloNumero;

  SchermataCoperti({required this.tavoloNumero});

  @override
  _SchermataCopertiState createState() => _SchermataCopertiState();
}

class _SchermataCopertiState extends State<SchermataCoperti> {
  int _numeroCoperti = 1;

  void _incrementaCoperti() {
    setState(() {
      if (_numeroCoperti < 30) {
        _numeroCoperti++;
      }
    });
  }

  void _decrementaCoperti() {
    setState(() {
      if (_numeroCoperti > 1) {
        _numeroCoperti--;
      }
    });
  }

  void _vaiASchermataMenu(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            SchermataMenu(
              tavoloNumero: widget.tavoloNumero,
              numeroCoperti: _numeroCoperti,
              ordiniEsistenti: [], // Lista vuota per nuovo ordine
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Tavolo ${widget.tavoloNumero} - Coperti'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'Numero di coperti:',
              style: TextStyle(fontSize: 20),
            ),
            SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: <Widget>[
                ElevatedButton(
                  onPressed: _decrementaCoperti,
                  child: Text('-', style: TextStyle(fontSize: 30)),
                ),
                Text(
                  '$_numeroCoperti',
                  style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
                ),
                ElevatedButton(
                  onPressed: _incrementaCoperti,
                  child: Text('+', style: TextStyle(fontSize: 30)),
                ),
              ],
            ),
            SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, true);
                _vaiASchermataMenu(context);
              },
              child: Text('Conferma Coperti', style: TextStyle(fontSize: 20)),
            ),
          ],
        ),
      ),
    );
  }
}

class OrderItem {
  String name;
  int quantity;
  String note;
  bool isSeparator;

  OrderItem({
    required this.name,
    this.quantity = 0,
    this.note = '',
    this.isSeparator = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'quantity': quantity,
      'note': note,
      'isSeparator': isSeparator,
    };
  }
}

class SchermataMenu extends StatefulWidget {
  final int tavoloNumero;
  final int numeroCoperti;
  final List<OrderItem> ordiniEsistenti;

  SchermataMenu({
    required this.tavoloNumero,
    required this.numeroCoperti,
    this.ordiniEsistenti = const [],
  });

  @override
  _SchermataMenuState createState() => _SchermataMenuState();
}

class _SchermataMenuState extends State<SchermataMenu> {
  List<OrderItem> _originalOrderItems = []; // NUOVO: traccia ordine originale
  List<String> _currentMenuItems = [];
  List<OrderItem> _orderItems = [];
  bool _isOrderExpanded = false;
  final ScrollController _scrollController = ScrollController();
  String? _currentOrderId;
  bool _hasAutoExpanded = false; // NUOVO: traccia se già aperto automaticamente
  bool _orderSaved = false;

  @override
  void initState() {
    super.initState();

    // Carica gli ordini esistenti se ci sono
    if (widget.ordiniEsistenti.isNotEmpty) {
      _orderItems = List.from(widget.ordiniEsistenti);
      _originalOrderItems = List.from(widget.ordiniEsistenti);
      _loadCurrentOrderId();
      _isOrderExpanded = true;
    }

    // Ascolta i cambiamenti dei prezzi in tempo reale
    if (firebaseInitialized) {
      FirebaseFirestore.instance
          .collection('impostazioni')
          .doc('prezzi')
          .snapshots()
          .listen((snapshot) {
        print('🔍 LISTENER PREZZI ATTIVATO');
        if (snapshot.exists && mounted) {
          Map<String, dynamic> prezziFirebase = snapshot.data() ?? {};

          print('📊 FUORI MENÙ DA FIREBASE: ${prezziFirebase.keys.where((k) =>
              k.startsWith("FM:")).toList()}');

          setState(() {
            prezziFirebase.forEach((piatto, valore) {
              // Ignora i timestamp separati
              if (piatto.endsWith('_timestamp')) return;

              if (prezziMenu.containsKey(piatto)) {
                prezziMenu[piatto] = (valore as num).toDouble();
              } else if (piatto.startsWith('FM:')) {
                prezziMenu[piatto] = (valore as num).toDouble();
                print('🆕 FUORI MENÙ CARICATO: $piatto = €$valore');
              }
            });
          });

          print('📋 PREZZI LOCALI DOPO AGGIORNAMENTO:');
          prezziMenu.forEach((key, value) {
            if (key.startsWith('FM:')) {
              print('   $key = €$value');
            }
          });
        } else {
          print('❌ SNAPSHOT NON ESISTE O NON MOUNTED');
        }
      });

      // Caricamento forzato
      _caricaPrezziImmediato();
    } else {
      print('❌ FIREBASE NON INIZIALIZZATO IN INITSTATE');
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Carica l'ID dell'ordine esistente per questo tavolo
  Future<void> _loadCurrentOrderId() async {
    if (!firebaseInitialized) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('ordini')
          .where('tavoloNumero', isEqualTo: widget.tavoloNumero)
          .where('status', isEqualTo: 'active')
          .get();

      if (snapshot.docs.isNotEmpty) {
        _currentOrderId = snapshot.docs.first.id;
      }
    } catch (e) {
      print('Errore caricamento ID ordine: $e');
    }
  }

  // NUOVO: Calcola solo gli items aggiunti
  List<OrderItem> _calcolaNuoviItems() {
    print('🔍 DEBUG CALCOLO NUOVI ITEMS');
    print('📊 Original length: ${_originalOrderItems.length}');
    print('📊 Current length: ${_orderItems.length}');

    List<OrderItem> nuoviItems = [];
    int originalLength = _originalOrderItems.length;

    // Prendi SOLO quello che è stato aggiunto DOPO gli items originali
    // NON controlliamo gli incrementi di quantità su items già esistenti!
    for (int i = originalLength; i < _orderItems.length; i++) {
      nuoviItems.add(_orderItems[i]);
      print('➕ Nuovo item in pos $i: ${_orderItems[i].name} x ${_orderItems[i].quantity}');
    }

    print('✅ Nuovi items da stampare: ${nuoviItems.map((e) => e.isSeparator ? e.name : '${e.name}x${e.quantity}').join(', ')}');

    return nuoviItems;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _caricaPrezziImmediato() async {
    if (!firebaseInitialized) return;

    try {
      print('🔄 CARICAMENTO FORZATO PREZZI...');
      final doc = await FirebaseFirestore.instance
          .collection('impostazioni')
          .doc('prezzi')
          .get();

      if (doc.exists) {
        Map<String, dynamic> prezziFirebase = doc.data() ?? {};

        setState(() {
          prezziFirebase.forEach((piatto, prezzo) {
            if (piatto.startsWith('FM:') && !piatto.endsWith('_timestamp')) {
              prezziMenu[piatto] = (prezzo as num).toDouble();
              print('✅ FM CARICATO FORZATAMENTE: $piatto = €$prezzo');
            }
          });
        });
      }
    } catch (e) {
      print('❌ Errore caricamento forzato: $e');
    }
  }

  void _showCategory(String category) {
    setState(() {
      switch (category) {
        case 'MENÙ':
          _currentMenuItems = [
            '➕ FUORI MENÙ',
            'FREDDI',
            'CALDI',
            'CALDI TOP',
            'INSALATA DI MARE',
            'D&G',
            'IMPEPATA',
            'SAUTÈ',
            'OSTRICHE',
            'CRUDI',
            'GRAN PLATEAU DI CRUDI',
            'CHITARRA VONGOLE',
            'GNOCCHI SCOGLIO',
            'PRIMO NOSTRO',
            'RISOTTO',
            'SPAGHETTI GLUTEN FREE',
            'FRITTURA SS',
            'FRITTURA MISTA',
            'FRITTURA SOLO CALAMARI',
            'GRIGLIATA MISTA',
            'SPIEDINO GRIGLIATO',
            'ORATA CON PATATE',
            'SPIGOLA CON PATATE',
            'PATATINE FRITTE',
            'VERDURA GRIGLIATA',
            'INSALATA MISTA',
            'PASTA CON POMODORO',
            'COTOLETTA E PATATINE',
          ];
          break;
        case 'BEVANDE':
          _currentMenuItems = [
            'ACQUA NAT',
            'ACQUA FRIZZ',
            'COCALITRO',
            'PERONI',
            'BIANCA PIPERITA',
            'LATTINA',
            'BIANCO - 0.75',
            'BIANCO - 0.50',
            'BIANCO - 0.25',
            'ROSATO - 0.75',
            'ROSATO - 0.50',
            'ROSATO - 0.25',
            'CALICE',
            'PECORINO AGRIVERDE',
            'PECORINO SUPERIORE',
            'GEWURZTRAMINER',
            'PASSERINA SPUMANTIZZATA',
            'ROSATO TESTAROSSA',
            'PASSERINA TESTAROSSA',
            'TREBBIANO FONTECUPA',
            'CERASUOLO FONTECUPA',
            'COCOCCIOLA',
            'CERASUOLO STRAPPELLI',
            'VILLAGEMMA',
            'MONTEPULCIANO ROSSO',
            'PROSECCO',
            'FERGHETTINA BIANCO',
            'FERGHETTINA ROSATO',
            'CÀ DEL BOSCO',
            'JIN TONIC LONDON',
            'JIN TONIC HENDRICKS'
          ];
          break;
        case 'DOLCI':
          _currentMenuItems = [
            'SORBETTO',
            'TIRAMISÙ',
            'CHEESECAKE PISTACCHIO',
            'CHEESECAKE NUTELLA',
            'CHEESECAKE FRUTTI DI BOSCO'
          ];
          break;
        case 'BAR':
          _currentMenuItems = [
            'CAFFÈ ESPRESSO',
            'CAFFÈ MACCHIATO',
            'CAFFÈ CORRETTO',
            'CAPPUCCINO',
            'AMARO',
            'RUM'
          ];
          break;
        default:
          _currentMenuItems = [];
      }
    });
  }

  void _incrementItem(String item) {
    if (item == '➕ FUORI MENÙ') {
      _mostraDialogFuoriMenu();
      return;
    }
    setState(() {
      // NUOVO: Apri automaticamente la finestra al primo articolo
      if (_orderItems.isEmpty && !_hasAutoExpanded) {
        _isOrderExpanded = true;
        _hasAutoExpanded = true;
      }

      // NUOVO: Controlla se ci sono separatori nell'ordine
      bool hasSeparators = _orderItems.any((orderItem) =>
      orderItem.isSeparator);

      if (hasSeparators) {
        // Se ci sono separatori, aggiungi SEMPRE in fondo senza cercare
        _orderItems.add(OrderItem(name: item, quantity: 1));
      } else {
        // Se non ci sono separatori, comportamento normale (cerca e incrementa)
        bool found = false;
        for (int i = 0; i < _orderItems.length; i++) {
          if (_orderItems[i].name == item && !_orderItems[i].isSeparator) {
            _orderItems[i].quantity++;
            found = true;
            break;
          }
        }
        if (!found) {
          _orderItems.add(OrderItem(name: item, quantity: 1));
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients && _isOrderExpanded) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _mostraDialogFuoriMenu() async {
    final nomeController = TextEditingController();
    final prezzoController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Inserisci Fuori Menù'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nomeController,
                decoration: InputDecoration(
                  labelText: 'Nome Piatto',
                  hintText: 'Es: Astice alla griglia',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.characters,
              ),
              SizedBox(height: 16),
              TextField(
                controller: prezzoController,
                decoration: InputDecoration(
                  labelText: 'Prezzo (€)',
                  hintText: 'Es: 35.00',
                  border: OutlineInputBorder(),
                  prefixText: '€ ',
                ),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
              ),
            ],
          ),
          actions: [
            TextButton(
              child: Text('Annulla'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              child: Text('Aggiungi'),
              onPressed: () async {
                String nomePiatto = nomeController.text.trim().toUpperCase();
                double? prezzo = double.tryParse(
                    prezzoController.text.replaceAll(',', '.'));

                if (nomePiatto.isNotEmpty) {
                  String chiaveFuoriMenu = 'FM: $nomePiatto';

                  // Aggiungi al menu prezzi locale
                  if (prezzo != null && prezzo > 0) {
                    prezziMenu[chiaveFuoriMenu] = prezzo;

                    // SALVA SU FIREBASE CON TIMESTAMP
                    if (firebaseInitialized) {
                      try {
                        // Recupera tutti i prezzi attuali da Firebase
                        final doc = await FirebaseFirestore.instance
                            .collection('impostazioni')
                            .doc('prezzi')
                            .get();

                        Map<String, dynamic> prezziFirebase = doc.exists ?
                        Map<String, dynamic>.from(doc.data() ?? {}) : {};

                        // NUOVO (più semplice)
                        prezziFirebase[chiaveFuoriMenu] = prezzo;
                        prezziFirebase['${chiaveFuoriMenu}_timestamp'] =
                            DateTime.now().toIso8601String();

                        // Salva tutto su Firebase
                        await FirebaseFirestore.instance
                            .collection('impostazioni')
                            .doc('prezzi')
                            .set(prezziFirebase);

                        print(
                            '✅ Fuori menù salvato su Firebase con timestamp: $chiaveFuoriMenu = €$prezzo');

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Aggiunto: $nomePiatto - €${prezzo
                                .toStringAsFixed(2)} (sincronizzato)'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      } catch (e) {
                        print(
                            '❌ Errore salvataggio fuori menù su Firebase: $e');
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                'Aggiunto localmente (non sincronizzato): $nomePiatto'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              'Aggiunto solo localmente (Firebase offline): $nomePiatto'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    }
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Aggiunto: $nomePiatto (senza prezzo)'),
                        backgroundColor: Colors.blue,
                      ),
                    );
                  }

                  // Aggiungi all'ordine
                  setState(() {
                    _orderItems.add(OrderItem(
                      name: chiaveFuoriMenu,
                      quantity: 1,
                    ));
                  });

                  Navigator.of(context).pop();
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _decrementItem(String item) {
    setState(() {
      for (int i = 0; i < _orderItems.length; i++) {
        if (_orderItems[i].name == item && !_orderItems[i].isSeparator) {
          _orderItems[i].quantity--;
          if (_orderItems[i].quantity <= 0) {
            _orderItems.removeAt(i);
          }
          break;
        }
      }
    });
  }

  void _incrementOrderItem(int index) {
    setState(() {
      if (index < _orderItems.length && !_orderItems[index].isSeparator) {
        _orderItems[index].quantity++;
      }
    });
  }

  void _decrementOrderItem(int index) {
    setState(() {
      if (index < _orderItems.length && !_orderItems[index].isSeparator) {
        if (_orderItems[index].quantity > 1) {
          _orderItems[index].quantity--;
        } else {
          _orderItems.removeAt(index);
        }
      }
    });
  }

  int _getItemQuantity(String item) {
    for (OrderItem orderItem in _orderItems) {
      if (orderItem.name == item && !orderItem.isSeparator) {
        return orderItem.quantity;
      }
    }
    return 0;
  }

  void _addSeparator() {
    setState(() {
      _orderItems.add(
          OrderItem(name: '--- SEPARATORE USCITA ---', isSeparator: true));
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients && _isOrderExpanded) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showNotesDialog(int index) async {
    final noteController = TextEditingController(text: _orderItems[index].note);

    await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Note per ${_orderItems[index].name}',
              style: TextStyle(fontSize: 20)),
          content: TextField(
            controller: noteController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Scrivi qui la nota...',
              border: OutlineInputBorder(),
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Annulla', style: TextStyle(fontSize: 16)),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: Text('Salva', style: TextStyle(fontSize: 16)),
              onPressed: () {
                setState(() {
                  _orderItems[index].note = noteController.text;
                });
                Navigator.of(context).pop(noteController.text);
              },
            ),
          ],
        );
      },
    );
  }

  // NUOVO: Dialog per scegliere dove stampare
  Future<void> _mostraDialogStampa() async {
    if (_orderItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nessun articolo da stampare'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Controlla se almeno una stampante è connessa
    final cucinaConnessa = printerService
        .getPrinter('cucina')
        ?.isConnected ?? false;
    final cassaConnessa = printerService
        .getPrinter('cassa')
        ?.isConnected ?? false;

    if (!cucinaConnessa && !cassaConnessa) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Configura prima le stampanti nelle impostazioni'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Dove vuoi stampare?', style: TextStyle(fontSize: 20)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Opzione Cucina
              ListTile(
                enabled: printerService
                    .getPrinter('cucina')
                    ?.isConnected ?? false,
                leading: Icon(Icons.restaurant, color: Colors.orange, size: 32),
                title: Text('CUCINA', style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
                subtitle: Text(
                  printerService
                      .getPrinter('cucina')
                      ?.isConnected ?? false
                      ? 'Solo pietanze (senza prezzi)'
                      : 'Non connessa',
                  style: TextStyle(
                      color: printerService
                          .getPrinter('cucina')
                          ?.isConnected ?? false ? Colors.grey : Colors.red
                  ),
                ),
                onTap: printerService
                    .getPrinter('cucina')
                    ?.isConnected ?? false ? () {
                  Navigator.of(context).pop();
                  _stampaOrdine('cucina');
                } : null,
              ),
              Divider(),
              // Opzione Cassa
              ListTile(
                enabled: printerService
                    .getPrinter('cassa')
                    ?.isConnected ?? false,
                leading: Icon(
                    Icons.point_of_sale, color: Colors.blue, size: 32),
                title: Text('CASSA', style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
                subtitle: Text(
                  printerService
                      .getPrinter('cassa')
                      ?.isConnected ?? false
                      ? 'Con prezzi e totale'
                      : 'Non connessa',
                  style: TextStyle(
                      color: printerService
                          .getPrinter('cassa')
                          ?.isConnected ?? false ? Colors.grey : Colors.red
                  ),
                ),
                onTap: printerService
                    .getPrinter('cassa')
                    ?.isConnected ?? false ? () {
                  Navigator.of(context).pop();
                  _stampaOrdine('cassa');
                } : null,
              ),
              if (_originalOrderItems.isNotEmpty) ...[
                Divider(),
                ListTile(
                  enabled: printerService
                      .getPrinter('cucina')
                      ?.isConnected ?? false,
                  leading: Icon(Icons.refresh, color: Colors.red, size: 32),
                  title: Text('RISTAMPA COMPLETA CUCINA', style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    printerService
                        .getPrinter('cucina')
                        ?.isConnected ?? false
                        ? 'Ristampa tutto l\'ordine (emergenza)'
                        : 'Non connessa',
                    style: TextStyle(
                        color: printerService
                            .getPrinter('cucina')
                            ?.isConnected ?? false ? Colors.grey : Colors.red
                    ),
                  ),
                  onTap: printerService
                      .getPrinter('cucina')
                      ?.isConnected ?? false ? () {
                    Navigator.of(context).pop();
                    _stampaOrdine('cucina_completa'); // Nota: parametro diverso
                  } : null,
                ),
              ],
              Divider(),
              // Opzione Entrambe
              ListTile(
                enabled: printerService
                    .getPrinter('cucina')
                    ?.isConnected == true &&
                    printerService
                        .getPrinter('cassa')
                        ?.isConnected == true,
                leading: Icon(
                    Icons.print_disabled, color: Colors.green, size: 32),
                title: Text('ENTRAMBE', style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
                subtitle: Text(
                  printerService
                      .getPrinter('cucina')
                      ?.isConnected == true &&
                      printerService
                          .getPrinter('cassa')
                          ?.isConnected == true
                      ? 'Stampa su entrambe le stampanti'
                      : 'Connetti entrambe le stampanti',
                  style: TextStyle(
                      color: printerService
                          .getPrinter('cucina')
                          ?.isConnected == true &&
                          printerService
                              .getPrinter('cassa')
                              ?.isConnected == true
                          ? Colors.grey : Colors.red
                  ),
                ),
                onTap: printerService
                    .getPrinter('cucina')
                    ?.isConnected == true &&
                    printerService
                        .getPrinter('cassa')
                        ?.isConnected == true ? () {
                  Navigator.of(context).pop();
                  _stampaOrdine('entrambe');
                } : null,
              ),
            ],
          ),
          actions: [
            TextButton(
              child: Text('Annulla', style: TextStyle(fontSize: 16)),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  // NUOVO: Stampa ordine usando le connessioni persistenti
  Future<void> _stampaOrdine(String destinazione) async {
    // NUOVO: Gestisci ristampa completa
    bool forzaStampaCompleta = false;
    if (destinazione == 'cucina_completa') {
      destinazione = 'cucina';
      forzaStampaCompleta = true;
    }

    if (destinazione == 'entrambe') {
      // Stampa su entrambe
      await _stampaOrdine('cucina');
      await _stampaOrdine('cassa');
      return;
    }

    final printer = printerService.getPrinter(destinazione);
    if (printer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Stampante $destinazione non trovata'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!printer.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Stampante ${printer
              .name} non connessa. Connettila dalle impostazioni.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final bool conPrezzi = destinazione == 'cassa';
    final String tipoStampa = printer.name;
    print(
        '🖨️ DEBUG - Destinazione: "$destinazione" | Con prezzi: $conPrezzi | Tipo: $tipoStampa');

    try {
      // Disconnetti e riconnetti prima di stampare
      print('🔄 Preparazione ${printer.name}...');
      printer.disconnect();
      await Future.delayed(Duration(milliseconds: 100));

      // Prova a connettersi fino a 3 volte
      bool connected = false;
      for (int i = 0; i < 3; i++) {
        if (await printer.connect()) {
          connected = true;
          print('✅ Connesso al tentativo ${i + 1}');
          break;
        }
        print('❌ Tentativo ${i + 1} fallito');
        await Future.delayed(Duration(milliseconds: 500));
      }

      if (!connected) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ${printer.name} non risponde dopo 3 tentativi'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'RIPROVA',
              textColor: Colors.white,
              onPressed: () => _stampaOrdine(destinazione),
            ),
          ),
        );
        return;
      }

      // Mostra che sta stampando
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🖨️ Stampa in corso su ${printer.name}...'),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 1),
        ),
      );

      final printerObj = printer.printer!;
      // Beep DOPO la dichiarazione di printerObj
      if (destinazione == 'cassa') {
        printerObj.beep(n: 1, duration: PosBeepDuration.beep250ms);
      } else {
        printerObj.beep(n: 6, duration: PosBeepDuration.beep250ms);
      }
      // NUOVO: Determina se è un aggiornamento
      bool isAggiornamento = destinazione == 'cucina' &&
          _originalOrderItems.isNotEmpty && !forzaStampaCompleta;
      List<OrderItem> itemsDaStampare = isAggiornamento
          ? _calcolaNuoviItems()
          : _orderItems;

// Se è un aggiornamento ma non ci sono nuovi items, avvisa
      if (isAggiornamento && itemsDaStampare.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Nessuna nuova pietanza da stampare'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Intestazione
      printerObj.text('SAPORI DI MARE',
          styles: PosStyles(
            align: PosAlign.center,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
          ));

      printerObj.text('--------------------------------',
          styles: PosStyles(align: PosAlign.center));

      // NUOVO: Se è un aggiornamento, stampalo
      if (isAggiornamento) {
        printerObj.text('*** AGGIORNAMENTO ***',
            styles: PosStyles(
              align: PosAlign.center,
              height: PosTextSize.size2,
              width: PosTextSize.size2,
              bold: true,
            ));
        printerObj.text('');
      }

      // Info tavolo
      printerObj.text('TAVOLO: ${widget.tavoloNumero}',
          styles: PosStyles(
            align: PosAlign.center,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
          ));

      printerObj.text('Coperti: ${widget.numeroCoperti}',
          styles: PosStyles(
            align: PosAlign.center,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
          ));

      final now = DateTime.now();
      printerObj.text(
          'Data: ${now.day}/${now.month}/${now.year} - ${now.hour}:${now.minute
              .toString().padLeft(2, '0')}',
          styles: PosStyles(align: PosAlign.center));

      printerObj.text('--------------------------------',
          styles: PosStyles(align: PosAlign.center));

      double totale = 0.0;

      print('🔍 DEBUG STAMPA - Item da stampare:');
      for (OrderItem item in itemsDaStampare) {
        if (!item.isSeparator) {
          double prezzo = prezziMenu[item.name] ?? 0.0;
          print('   ${item.name} -> Prezzo trovato: €$prezzo');
        }
      }

      // Debug prezzi
      print('🔍 DEBUG STAMPA - Prezzi fuori menù:');
      prezziMenu.forEach((key, value) {
        if (key.startsWith('FM:')) {
          print('   $key = €$value');
        }
      });

      // Stampa articoli
      for (OrderItem item in itemsDaStampare) {
        if (item.isSeparator) {
          printerObj.text('');
          printerObj.text('--- SEPARATORE USCITA ---',
              styles: PosStyles(align: PosAlign.center, bold: true));
          printerObj.text('');
        } else {
          if (conPrezzi) {
            // STAMPA CASSA - CON PREZZI
            double prezzo = prezziMenu[item.name] ?? 0.0;
            double subtotale = prezzo * item.quantity;
            totale += subtotale;

            // Stampa articolo con prezzo
            printerObj.row([
              PosColumn(
                text: '${item.quantity}x ${item.name}',
                width: 8,
                styles: PosStyles(align: PosAlign.left),
              ),
              PosColumn(
                text: 'EUR ${subtotale.toStringAsFixed(2)}',
                width: 4,
                styles: PosStyles(align: PosAlign.right),
              ),
            ]);

            // Note (se presenti)
            if (item.note.isNotEmpty) {
              printerObj.text('   Nota: ${item.note}',
                  styles: PosStyles(align: PosAlign.left));
            }
          } else {
            // STAMPA CUCINA - SOLO PIETANZE GRANDI
            printerObj.text('${item.quantity}x ${item.name}',
                styles: PosStyles(
                  align: PosAlign.left,
                  height: PosTextSize.size2, // CAMBIATO DA size3 A size2
                  width: PosTextSize.size2, // CAMBIATO DA size3 A size2
                  bold: true,
                ));

// Note (se presenti)
            if (item.note.isNotEmpty) {
              printerObj.text('   Nota: ${item.note}',
                  styles: PosStyles(
                    align: PosAlign.left,
                    height: PosTextSize.size2,
                    width: PosTextSize.size2,
                  ));
            }
            printerObj.text(''); // Riga vuota tra articoli
          }
        }
      }

      // Footer
      printerObj.text('--------------------------------',
          styles: PosStyles(align: PosAlign.center));

      if (conPrezzi) {
        // Calcola e stampa coperti
        double costoCoperti = (prezziMenu['COPERTO'] ?? 3.0) *
            widget.numeroCoperti;

        printerObj.row([
          PosColumn(
            text: '${widget.numeroCoperti}x Coperto',
            width: 8,
            styles: PosStyles(align: PosAlign.left),
          ),
          PosColumn(
            text: 'EUR ${costoCoperti.toStringAsFixed(2)}',
            width: 4,
            styles: PosStyles(align: PosAlign.right),
          ),
        ]);

        printerObj.text('--------------------------------',
            styles: PosStyles(align: PosAlign.center));

        // TOTALE con coperti
        double totaleConCoperti = totale + costoCoperti;
        printerObj.text('TOTALE: EUR ${totaleConCoperti.toStringAsFixed(2)}',
            styles: PosStyles(
              align: PosAlign.center,
              height: PosTextSize.size2,
              width: PosTextSize.size2,
              bold: true,
            ));
        printerObj.text('');
      }

      printerObj.text(tipoStampa,
          styles: PosStyles(
            align: PosAlign.center,
            height: PosTextSize.size1,
            width: PosTextSize.size1,
          ));

      printerObj.feed(2);
      printerObj.cut();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '✅ Ordine stampato su $tipoStampa (connessione persistente)!'),
          backgroundColor: Colors.green,
        ),
      );

      // NUOVO: Aggiorna gli items originali solo dopo una stampa riuscita
      if (destinazione == 'cucina' || destinazione == 'cucina_completa') {
        setState(() {
          _originalOrderItems = List.from(_orderItems);
          print('📸 SNAPSHOT AGGIORNATO: ${_originalOrderItems.map((e) => '${e
              .name}x${e.quantity}').join(', ')}');
        });
      }
    } catch (e) {
      // Se c'è un errore, prova a riconnettere
      await printer.connect();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore stampa $tipoStampa: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // GESTIONE ORDINI NUOVI E MODIFICHE
  void _confermaOrdine() async {
    print('🔥 === CONFERMA ORDINE CON FIREBASE SAFE ===');

    if (_orderItems.isEmpty) {
      print('❌ Ordine vuoto');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Aggiungi almeno un articolo all\'ordine'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!firebaseInitialized) {
      print('⚠️ Firebase non disponibile - salvataggio locale');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ Ordine salvato localmente (Firebase offline)'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      print('🔥 Firebase Dispinobile - salvataggio su cloud...');

      if (_currentOrderId != null) {
        // MODIFICA ORDINE ESISTENTE
        print('🔄 Aggiornamento ordine esistente: $_currentOrderId');
        await FirebaseFirestore.instance.collection('ordini').doc(
            _currentOrderId).update({
          'items': _orderItems.map((item) => item.toMap()).toList(),
          'lastUpdate': FieldValue.serverTimestamp(),
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🔄 Ordine aggiornato su Firebase!'),
            backgroundColor: Colors.blue,
          ),
        );
      } else {
        // NUOVO ORDINE
        final uuid = Uuid();
        final ordineId = uuid.v4();
        _currentOrderId = ordineId;

        await FirebaseFirestore.instance.collection('ordini').doc(ordineId).set(
            {
              'id': ordineId,
              'tavoloNumero': widget.tavoloNumero,
              'numeroCoperti': widget.numeroCoperti,
              'items': _orderItems.map((item) => item.toMap()).toList(),
              'timestamp': FieldValue.serverTimestamp(),
              'status': 'active',
            });

        print('✅ Nuovo ordine salvato su Firebase!');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🔥 Ordine salvato su Firebase!'),
            backgroundColor: Colors.green,
          ),
        );
      }

      setState(() {
        _originalOrderItems = List.from(_orderItems);
        _orderSaved = true;
      });
    } catch (e) {
      print('❌ Errore Firebase: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Errore Firebase - salvato localmente'),
          backgroundColor: Colors.red,
        ),
      );

      setState(() {
        _originalOrderItems = List.from(_orderItems);
        _orderSaved = true;
      });
    }
  }

  Future<void> _onBackPressed() async {
    // Se l'ordine è vuoto o già salvato, esci direttamente
    if (_orderItems.isEmpty || _orderSaved) {
      Navigator.pop(context);
      return;
    }

    // Confronto robusto: controlla se l'ordine è stato modificato
    bool isModificato = false;

    if (_orderItems.length != _originalOrderItems.length) {
      isModificato = true;
    } else {
      // Confronta ogni item
      for (int i = 0; i < _orderItems.length; i++) {
        if (_orderItems[i].name != _originalOrderItems[i].name ||
            _orderItems[i].quantity != _originalOrderItems[i].quantity ||
            _orderItems[i].note != _originalOrderItems[i].note ||
            _orderItems[i].isSeparator != _originalOrderItems[i].isSeparator) {
          isModificato = true;
          break;
        }
      }
    }

    // Se NON è modificato, esci direttamente
    if (!isModificato) {
      Navigator.pop(context);
      return;
    }

    // Mostra dialog di conferma
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('⚠️ ATTENZIONE'),
        content: Text('Ci sono modifiche non salvate.\n\nVuoi uscire senza salvare?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('ESCI SENZA SALVARE', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      Navigator.pop(context);
    }
  }

  Future<void> _onHomePressed() async {
    // Se l'ordine è vuoto o già salvato, vai a home direttamente
    if (_orderItems.isEmpty || _orderSaved) {
      Navigator.popUntil(context, (route) => route.isFirst);
      return;
    }

    // Confronto robusto: controlla se l'ordine è stato modificato
    bool isModificato = false;

    if (_orderItems.length != _originalOrderItems.length) {
      isModificato = true;
    } else {
      // Confronta ogni item
      for (int i = 0; i < _orderItems.length; i++) {
        if (_orderItems[i].name != _originalOrderItems[i].name ||
            _orderItems[i].quantity != _originalOrderItems[i].quantity ||
            _orderItems[i].note != _originalOrderItems[i].note ||
            _orderItems[i].isSeparator != _originalOrderItems[i].isSeparator) {
          isModificato = true;
          break;
        }
      }
    }

    // Se NON è modificato, vai a home direttamente
    if (!isModificato) {
      Navigator.popUntil(context, (route) => route.isFirst);
      return;
    }

    // Mostra dialog di conferma
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('⚠️ ATTENZIONE'),
        content: Text('Ci sono modifiche non salvate.\n\nVuoi uscire senza salvare?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('ESCI SENZA SALVARE', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      Navigator.popUntil(context, (route) => route.isFirst);
    }
  }

  Widget _buildCategoryButton(String text, Color color) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: InkWell(
          onTap: () => _showCategory(text),
          child: Container(
            height: 60,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8.0),
            ),
            child: Center(
              child: FittedBox( // AGGIUNTO
                fit: BoxFit.scaleDown, // AGGIUNTO
                child: Padding( // AGGIUNTO
                  padding: EdgeInsets.symmetric(horizontal: 8.0), // AGGIUNTO
                  child: Text(
                    text,
                    style: TextStyle(
                        fontSize: 18,
                        color: Colors.white,
                        fontWeight: FontWeight.bold
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Se l'ordine è vuoto, salvato, o non modificato, lascia uscire
        if (_orderItems.isEmpty || _orderSaved || _orderItems.length == _originalOrderItems.length && _orderItems.toString() == _originalOrderItems.toString()) {
          return true;
        }

        // Mostra dialog di conferma
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) =>
              AlertDialog(
                title: Text('⚠️ ATTENZIONE'),
                content: Text(
                    'Ci sono modifiche non salvate.\n\nVuoi uscire senza salvare?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text('Annulla'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text('ESCI SENZA SALVARE',
                        style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
        );

        return confirm ?? false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Menù ${firebaseInitialized ? "🔥" : "📴"}',
              style: TextStyle(fontSize: 22)),
          leading: IconButton(
            icon: Icon(Icons.arrow_back),
            onPressed: _onBackPressed,
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: ElevatedButton(
                onPressed: _onHomePressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                ),
                child: Text('Home',
                    style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: ElevatedButton(
                onPressed: _confermaOrdine,
                style: ElevatedButton.styleFrom(
                  backgroundColor: firebaseInitialized ? Colors.green : Colors
                      .orange,
                ),
                child: Text(
                    _currentOrderId != null ? 'Aggiorna' : 'Conferma',
                    style: TextStyle(color: Colors.white, fontSize: 16)
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: ElevatedButton(
                onPressed: _addSeparator,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                ),
                child: Text('Barra',
                    style: TextStyle(color: Colors.white, fontSize: 18)),
              ),
            ),
            Padding(  // ← AGGIUNGI QUESTO PADDING
              padding: EdgeInsets.only(right: 50.0),  // ← SPAZIO A DESTRA
              child: IconButton(
                icon: Icon(Icons.print, color: Colors.white),  // ← GIALLO E GRANDE
                onPressed: _mostraDialogStampa,
                tooltip: 'Stampa Ordine',
              ),
            ),  // ← CHIUDE IL PADDING
          ],  // ← CHIUDE actions
        ),  // ← CHIUDE AppBar
        backgroundColor: Colors.black,
        body: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: <Widget>[
                  _buildCategoryButton('MENÙ', Colors.blue),
                  _buildCategoryButton('BEVANDE', Colors.green),
                  _buildCategoryButton('DOLCI', Colors.orange),
                  _buildCategoryButton('BAR', Colors.purple),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: _currentMenuItems.isEmpty
                  ? Center(
                child: Text(
                  'Seleziona una categoria per visualizzare i piatti',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                  textAlign: TextAlign.center,
                ),
              )
                  : ListView.builder(
                itemCount: _currentMenuItems.length,
                itemBuilder: (context, index) {
                  final item = _currentMenuItems[index];
                  final quantity = _getItemQuantity(item);
                  return Card(
                    color: Colors.grey.shade900,
                    margin: EdgeInsets.symmetric(
                        horizontal: 8.0, vertical: 4.0),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              item,
                              style: TextStyle(color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              SizedBox(
                                width: 40,
                                height: 40,
                                child: ElevatedButton(
                                  onPressed: () => _decrementItem(item),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    padding: EdgeInsets.zero,
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                            8.0)),
                                  ),
                                  child: Icon(Icons.remove, color: Colors.white,
                                      size: 20),
                                ),
                              ),
                              SizedBox(width: 8),
                              Container(
                                width: 30,
                                child: Text(
                                  '$quantity',
                                  style: TextStyle(color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                              SizedBox(width: 8),
                              SizedBox(
                                width: 40,
                                height: 40,
                                child: ElevatedButton(
                                  onPressed: () => _incrementItem(item),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    padding: EdgeInsets.zero,
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                            8.0)),
                                  ),
                                  child: Icon(
                                      Icons.add, color: Colors.white, size: 20),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => _isOrderExpanded = !_isOrderExpanded),
              child: Container(
                color: Colors.grey.shade800,
                padding: EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _currentOrderId != null
                              ? 'Modifica Ordine:'
                              : 'Ordine Attuale:',
                          style: TextStyle(color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold),
                        ),
                        Icon(
                          _isOrderExpanded ? Icons.keyboard_arrow_down : Icons
                              .keyboard_arrow_up,
                          color: Colors.white,
                          size: 24,
                        ),
                      ],
                    ),
                    if (_isOrderExpanded) ...[
                      Padding(
                        padding: const EdgeInsets.only(left: 8.0, top: 6.0),
                        child: Text(
                          'Tavolo: ${widget.tavoloNumero} - Coperti: ${widget
                              .numeroCoperti}',
                          style: TextStyle(color: Colors.yellow,
                              fontSize: 24,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (_orderItems.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 8.0, top: 6.0),
                          child: Text(
                            'Nessun articolo nell\'ordine.',
                            style: TextStyle(color: Colors.grey, fontSize: 18),
                          ),
                        )
                      else
                        Container(
                          height: 320,
                          child: ReorderableListView.builder(
                            scrollController: _scrollController,
                            itemCount: _orderItems.length,
                            itemBuilder: (context, index) {
                              final orderItem = _orderItems[index];
                              return Container(
                                key: ValueKey('${orderItem.name}_$index'),
                                margin: EdgeInsets.symmetric(vertical: 1.0),
                                child: Card(
                                  color: orderItem.isSeparator ? Colors.orange
                                      .shade700 : Colors.grey.shade700,
                                  child: Padding(
                                    padding: const EdgeInsets.all(4.0),
                                    child: Row(
                                      children: [
                                        Icon(Icons.drag_handle,
                                            color: Colors.white),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment
                                                .start,
                                            children: [
                                              Text(
                                                orderItem.isSeparator
                                                    ? orderItem.name
                                                    : '${orderItem
                                                    .name} x ${orderItem
                                                    .quantity}',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                  fontWeight: orderItem
                                                      .isSeparator ? FontWeight
                                                      .bold : FontWeight.normal,
                                                ),
                                              ),
                                              if (!orderItem.isSeparator)
                                                Padding(
                                                  padding: EdgeInsets.only(
                                                      top: 8.0),
                                                  child: Row(
                                                    mainAxisAlignment: MainAxisAlignment
                                                        .center,
                                                    children: [
                                                      ElevatedButton(
                                                        onPressed: () =>
                                                            _decrementOrderItem(
                                                                index),
                                                        child: Text('-',
                                                            style: TextStyle(
                                                                fontSize: 18)),
                                                        style: ElevatedButton
                                                            .styleFrom(
                                                          backgroundColor: Colors
                                                              .red,
                                                          minimumSize: Size(
                                                              40, 30),
                                                        ),
                                                      ),
                                                      SizedBox(width: 12),
                                                      Text(
                                                        '${orderItem.quantity}',
                                                        style: TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 16,
                                                            fontWeight: FontWeight
                                                                .bold),
                                                      ),
                                                      SizedBox(width: 12),
                                                      ElevatedButton(
                                                        onPressed: () =>
                                                            _incrementOrderItem(
                                                                index),
                                                        child: Text('+',
                                                            style: TextStyle(
                                                                fontSize: 18)),
                                                        style: ElevatedButton
                                                            .styleFrom(
                                                          backgroundColor: Colors
                                                              .green,
                                                          minimumSize: Size(
                                                              40, 30),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              if (orderItem.note.isNotEmpty)
                                                Padding(
                                                  padding: EdgeInsets.only(
                                                      top: 4.0),
                                                  child: Text(
                                                    'Nota: ${orderItem.note}',
                                                    style: TextStyle(
                                                        color: Colors.grey
                                                            .shade300,
                                                        fontSize: 14),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        if (!orderItem.isSeparator) ...[
                                          ElevatedButton(
                                            onPressed: () =>
                                                _showNotesDialog(index),
                                            child: Text('Note',
                                                style: TextStyle(fontSize: 14)),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.blueGrey,
                                              foregroundColor: Colors.white,
                                              padding: EdgeInsets.symmetric(
                                                  horizontal: 12, vertical: 8),
                                            ),
                                          ),
                                          SizedBox(width: 8),
                                          IconButton(
                                            onPressed: () {
                                              setState(() {
                                                _orderItems.removeAt(index);
                                              });
                                            },
                                            icon: Icon(Icons.delete,
                                                color: Colors.red),
                                            tooltip: 'Elimina pietanza',
                                          ),
                                        ],
                                        if (orderItem.isSeparator)
                                          IconButton(
                                            onPressed: () {
                                              setState(() {
                                                _orderItems.removeAt(index);
                                              });
                                            },
                                            icon: Icon(Icons.delete,
                                                color: Colors.red),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                            onReorder: (oldIndex, newIndex) {
                              setState(() {
                                if (newIndex > oldIndex) {
                                  newIndex -= 1;
                                }
                                final OrderItem item = _orderItems.removeAt(
                                    oldIndex);
                                _orderItems.insert(newIndex, item);
                              });
                            },
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// Dialog per modificare coperti
class _DialogModificaCoperti extends StatefulWidget {
  final int tavoloNumero;
  final int copertiAttuali;

  _DialogModificaCoperti({
    required this.tavoloNumero,
    required this.copertiAttuali,
  });

  @override
  _DialogModificaCopertiState createState() => _DialogModificaCopertiState();
}

class _DialogModificaCopertiState extends State<_DialogModificaCoperti> {
  late int _numeroCoperti;

  @override
  void initState() {
    super.initState();
    _numeroCoperti = widget.copertiAttuali;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Modifica Coperti - Tavolo ${widget.tavoloNumero}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Coperti attuali: ${widget.copertiAttuali}'),
          SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              ElevatedButton(
                onPressed: () {
                  if (_numeroCoperti > 1) {
                    setState(() => _numeroCoperti--);
                  }
                },
                child: Text('-', style: TextStyle(fontSize: 24)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              ),
              Text(
                '$_numeroCoperti',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              ElevatedButton(
                onPressed: () {
                  if (_numeroCoperti < 30) {
                    setState(() => _numeroCoperti++);
                  }
                },
                child: Text('+', style: TextStyle(fontSize: 24)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Annulla'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _numeroCoperti),
          child: Text('Conferma'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
        ),
      ],
    );
  }
}