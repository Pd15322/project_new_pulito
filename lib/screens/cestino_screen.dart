import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../cestino_manager.dart';
import '../main.dart';

class CestinoScreen extends StatefulWidget {
  final Function(int tavoloNumero)? onRecupera;

  CestinoScreen({this.onRecupera});

  @override
  _CestinoScreenState createState() => _CestinoScreenState();
}

class _CestinoScreenState extends State<CestinoScreen> {
  List<OrdineCestino> _ordiniCestino = [];
  bool _isLoading = false;
  Set<String> _ordiniSelezionati = {};
  Map<int, bool> _tavoliOccupati = {};

  @override
  void initState() {
    super.initState();
    _caricaCestino();
    _caricaStatoTavoli();
  }

  Future<void> _caricaStatoTavoli() async {
    if (!firebaseInitialized) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('ordini')
          .where('status', isEqualTo: 'active')
          .get();

      Map<int, bool> tavoliOccupati = {};
      for (var doc in snapshot.docs) {
        int tavoloNumero = doc.data()['tavoloNumero'];
        tavoliOccupati[tavoloNumero] = true;
      }

      setState(() {
        _tavoliOccupati = tavoliOccupati;
      });
    } catch (e) {
      print('Errore caricamento stato tavoli: $e');
    }
  }

  Future<void> _caricaCestino() async {
    setState(() => _isLoading = true);

    try {
      await CestinoManager().puliziaAutomatica();
      final ordini = await CestinoManager().getOrdiniCestino();

      print('🗑️ Ordini nel cestino: ${ordini.length}');

      setState(() {
        _ordiniCestino = ordini;
        _isLoading = false;
      });
    } catch (e) {
      print('Errore caricamento cestino: $e');
      setState(() => _isLoading = false);
    }
  }

  String _formatTempoRimanente(Duration durata) {
    if (durata.isNegative) return 'Scaduto';

    final ore = durata.inHours;
    final minuti = durata.inMinutes % 60;

    if (ore > 0) {
      return '$ore ore, $minuti min';
    } else {
      return '$minuti minuti';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Cestino Ordini (${_ordiniCestino.length})'),
        actions: [
          if (_ordiniSelezionati.isNotEmpty)
            IconButton(
              icon: Icon(Icons.delete_sweep, color: Colors.red),
              onPressed: _eliminaSelezionati,
              tooltip: 'Elimina ${_ordiniSelezionati.length} selezionati',
            ),
          if (_ordiniCestino.isNotEmpty)
            IconButton(
              icon: Icon(Icons.delete_forever, color: Colors.orange),
              onPressed: _svuotaCestino,
              tooltip: 'Svuota tutto il cestino',
            ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _ordiniCestino.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete_outline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Il cestino è vuoto',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ],
        ),
      )
          : ListView.builder(
        itemCount: _ordiniCestino.length,
        itemBuilder: (context, index) {
          final ordine = _ordiniCestino[index];

          return Card(
            margin: EdgeInsets.all(8),
            child: ListTile(
              leading: Checkbox(
                value: _ordiniSelezionati.contains(ordine.id),
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      _ordiniSelezionati.add(ordine.id);
                    } else {
                      _ordiniSelezionati.remove(ordine.id);
                    }
                  });
                },
              ),
              title: Row(
                children: [
                  Text('Tavolo ${ordine.tavoloOriginale}'),
                  SizedBox(width: 8),
                  Icon(
                    Icons.circle,
                    size: 12,
                    color: _tavoliOccupati[ordine.tavoloOriginale] == true ? Colors.red : Colors.green,
                  ),
                  SizedBox(width: 4),
                  Text(
                    _tavoliOccupati[ordine.tavoloOriginale] == true ? 'Occupato' : 'Libero',
                    style: TextStyle(
                      fontSize: 12,
                      color: _tavoliOccupati[ordine.tavoloOriginale] == true ? Colors.red : Colors.green,
                    ),
                  ),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Eliminato: ${ordine.dataEliminazione.day}/${ordine.dataEliminazione.month}/${ordine.dataEliminazione.year} alle ${ordine.dataEliminazione.hour}:${ordine.dataEliminazione.minute.toString().padLeft(2, '0')}'),
                  Text('Scade tra: ${_formatTempoRimanente(ordine.tempoRimanente)}'),
                  Text('Totale: €${ordine.totale.toStringAsFixed(2)}'),
                  Text('Items: ${ordine.items.length}'),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.restore, color: Colors.green),
                    onPressed: () => _recuperaOrdine(ordine),
                    tooltip: 'Recupera ordine',
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_forever, color: Colors.red),
                    onPressed: () => _eliminaDefinitivamente(ordine),
                    tooltip: 'Elimina definitivamente',
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

    Future<void> _eliminaSelezionati() async {
      if (_ordiniSelezionati.isEmpty) return;

      final conferma = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Elimina selezionati'),
          content: Text(
              'Eliminare definitivamente ${_ordiniSelezionati.length} ordini?\n'
                  'Questa azione non può essere annullata.'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Annulla'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Elimina', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );

      if (conferma == true) {
        await CestinoManager().rimuoviMultipli(_ordiniSelezionati.toList());
        setState(() {
          _ordiniSelezionati.clear();
        });
        await _caricaCestino();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ordini eliminati definitivamente')),
        );
      }
    }

    Future<void> _svuotaCestino() async {
      final conferma = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Svuota cestino'),
          content: Text(
              'Eliminare definitivamente TUTTI gli ordini nel cestino?\n'
                  'Questa azione non può essere annullata.'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Annulla'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Svuota tutto', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );

      if (conferma == true) {
        await CestinoManager().svuotaCestino();
        setState(() {
          _ordiniCestino.clear();
          _ordiniSelezionati.clear();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cestino svuotato completamente')),
        );

        Navigator.pop(context);
      }
    }

  Future<void> _recuperaOrdine(OrdineCestino ordine) async {
    // Controlla se il tavolo originale è libero
    bool tavoloOriginaleLibero = !(_tavoliOccupati[ordine.tavoloOriginale] ?? false);
    int tavoloScelto = ordine.tavoloOriginale;

    if (!tavoloOriginaleLibero) {
      // Il tavolo originale è occupato, mostra dialog per scegliere
      final nuovoTavolo = await showDialog<int>(
        context: context,
        builder: (context) => _DialogSceltaTavolo(
          tavoloOriginale: ordine.tavoloOriginale,
          tavoliOccupati: _tavoliOccupati,
        ),
      );

      if (nuovoTavolo == null) return; // Annullato
      tavoloScelto = nuovoTavolo;
    }

    if (firebaseInitialized) {
      try {
        // Ricrea l'ordine su Firebase con il tavolo scelto
        await FirebaseFirestore.instance.collection('ordini').doc(ordine.id).set({
          'id': ordine.id,
          'tavoloNumero': tavoloScelto,  // <-- USA IL TAVOLO SCELTO
          'numeroCoperti': ordine.numeroCoperti,
          'items': ordine.items,
          'timestamp': FieldValue.serverTimestamp(),
          'status': 'active',
        });

        // Rimuovi dal cestino
        await CestinoManager().rimuoviDalCestino(ordine.id);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                tavoloScelto == ordine.tavoloOriginale
                    ? 'Ordine recuperato su Tavolo $tavoloScelto'
                    : 'Ordine recuperato su Tavolo $tavoloScelto (era Tavolo ${ordine.tavoloOriginale})'
            ),
            backgroundColor: Colors.green,
          ),
        );

        // Ricarica il cestino
        await _caricaCestino();

        // Se non ci sono più ordini, torna indietro
        if (_ordiniCestino.isEmpty) {
          Navigator.pop(context);
        }
      } catch (e) {
        print('Errore recupero ordine: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore nel recupero ordine'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _eliminaDefinitivamente(OrdineCestino ordine) async {
    final conferma = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Conferma eliminazione'),
        content: Text('Eliminare definitivamente questo ordine?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Elimina', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (conferma == true) {
      await CestinoManager().rimuoviDalCestino(ordine.id);
      await _caricaCestino();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ordine eliminato definitivamente')),
      );
    }
  }
}

// Dialog per scegliere un nuovo tavolo
class _DialogSceltaTavolo extends StatelessWidget {
  final int tavoloOriginale;
  final Map<int, bool> tavoliOccupati;

  _DialogSceltaTavolo({
    required this.tavoloOriginale,
    required this.tavoliOccupati,
  });

  @override
  Widget build(BuildContext context) {
    // Ottieni lista tavoli liberi
    List<int> tavoliLiberi = [];
    for (int i = 1; i <= 30; i++) {
      if (tavoliOccupati[i] != true) {
        tavoliLiberi.add(i);
      }
    }

    return AlertDialog(
      title: Text('Seleziona nuovo tavolo'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Il Tavolo $tavoloOriginale è occupato.\n'
                'Seleziona un tavolo libero per recuperare l\'ordine:',
          ),
          SizedBox(height: 16),
          Container(
            width: double.maxFinite,
            height: 200,
            child: GridView.builder(
              shrinkWrap: true,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                childAspectRatio: 1.5,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: tavoliLiberi.length,
              itemBuilder: (context, index) {
                final tavolo = tavoliLiberi[index];
                return InkWell(
                  onTap: () => Navigator.pop(context, tavolo),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        '$tavolo',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Annulla'),
        ),
      ],
    );
  }
}