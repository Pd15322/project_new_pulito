import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class OrdineCestino {
  final String id;
  final int tavoloOriginale;
  final int numeroCoperti;
  final List<Map<String, dynamic>> items;
  final DateTime dataEliminazione;
  final double totale;

  OrdineCestino({
    required this.id,
    required this.tavoloOriginale,
    required this.numeroCoperti,
    required this.items,
    required this.dataEliminazione,
    required this.totale,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'tavoloOriginale': tavoloOriginale,
    'numeroCoperti': numeroCoperti,
    'items': items,
    'dataEliminazione': dataEliminazione.toIso8601String(),
    'totale': totale,
  };

  factory OrdineCestino.fromJson(Map<String, dynamic> json) => OrdineCestino(
    id: json['id'],
    tavoloOriginale: json['tavoloOriginale'],
    numeroCoperti: json['numeroCoperti'],
    items: List<Map<String, dynamic>>.from(json['items']),
    dataEliminazione: DateTime.parse(json['dataEliminazione']),
    totale: json['totale'].toDouble(),
  );

  // Calcola tempo rimanente prima dell'eliminazione (24 ore)
  Duration get tempoRimanente {
    final scadenza = dataEliminazione.add(Duration(hours: 24));
    return scadenza.difference(DateTime.now());
  }

  bool get isScaduto => tempoRimanente.isNegative;
}

class CestinoManager {
  static const String _key = 'cestino_ordini';

  // Singleton
  static final CestinoManager _instance = CestinoManager._internal();
  factory CestinoManager() => _instance;
  CestinoManager._internal();

  // Aggiungi ordine al cestino
  Future<void> aggiungiAlCestino({
    required String ordineId,
    required int tavoloNumero,
    required int numeroCoperti,
    required List<Map<String, dynamic>> items,
    required double totale,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // Carica cestino esistente
    List<OrdineCestino> cestino = await getOrdiniCestino();

    // Aggiungi nuovo ordine
    cestino.add(OrdineCestino(
      id: ordineId,
      tavoloOriginale: tavoloNumero,
      numeroCoperti: numeroCoperti,
      items: items,
      dataEliminazione: DateTime.now(),
      totale: totale,
    ));

    // Salva
    await _salvaCestino(cestino);
    print('📥 Ordine tavolo $tavoloNumero aggiunto al cestino');
  }

  // Recupera tutti gli ordini nel cestino
  Future<List<OrdineCestino>> getOrdiniCestino() async {
    final prefs = await SharedPreferences.getInstance();
    final String? cestinoJson = prefs.getString(_key);

    if (cestinoJson == null) return [];

    List<dynamic> cestinoList = json.decode(cestinoJson);
    return cestinoList.map((e) => OrdineCestino.fromJson(e)).toList();
  }

  // Recupera un ordine specifico
  Future<OrdineCestino?> getOrdine(String ordineId) async {
    final cestino = await getOrdiniCestino();
    try {
      return cestino.firstWhere((o) => o.id == ordineId);
    } catch (e) {
      return null;
    }
  }

  // Rimuovi ordine dal cestino
  Future<void> rimuoviDalCestino(String ordineId) async {
    List<OrdineCestino> cestino = await getOrdiniCestino();
    cestino.removeWhere((o) => o.id == ordineId);
    await _salvaCestino(cestino);
  }

  // Rimuovi multipli ordini
  Future<void> rimuoviMultipli(List<String> ordiniIds) async {
    List<OrdineCestino> cestino = await getOrdiniCestino();
    cestino.removeWhere((o) => ordiniIds.contains(o.id));
    await _salvaCestino(cestino);
  }

  // Svuota completamente il cestino
  Future<void> svuotaCestino() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  // Pulizia automatica ordini > 24 ore
  Future<int> puliziaAutomatica() async {
    List<OrdineCestino> cestino = await getOrdiniCestino();
    final int iniziali = cestino.length;

    // Rimuovi ordini scaduti
    cestino.removeWhere((ordine) => ordine.isScaduto);

    await _salvaCestino(cestino);
    final int rimossi = iniziali - cestino.length;

    if (rimossi > 0) {
      print('🗑️ Pulizia automatica: rimossi $rimossi ordini scaduti');
    }

    return rimossi;
  }

  // Conta ordini nel cestino
  Future<int> contaOrdini() async {
    final cestino = await getOrdiniCestino();
    return cestino.length;
  }

  // Salva cestino in SharedPreferences
  Future<void> _salvaCestino(List<OrdineCestino> cestino) async {
    final prefs = await SharedPreferences.getInstance();
    final String cestinoJson = json.encode(
        cestino.map((e) => e.toJson()).toList()
    );
    await prefs.setString(_key, cestinoJson);
  }
}