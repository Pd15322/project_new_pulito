import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../main.dart';

// Password condivisa per tutti i dipendenti
const String EMPLOYEE_PASSWORD = "sdm16";

class GestioneDipendentiScreen extends StatefulWidget {
  @override
  _GestioneDipendentiScreenState createState() => _GestioneDipendentiScreenState();
}

class _GestioneDipendentiScreenState extends State<GestioneDipendentiScreen> {
  final _nomeController = TextEditingController();
  
  Future<void> _aggiungiDipendente() async {
    final nome = _nomeController.text.trim();
    
    if (nome.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Inserisci il nome del dipendente'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!firebaseInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Firebase non disponibile'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      // Usa il nome come ID (lowercase e senza spazi)
      final id = nome.toLowerCase().replaceAll(' ', '_');
      
      // Controlla se esiste già
      final existingDoc = await FirebaseFirestore.instance
          .collection('dipendenti')
          .doc(id)
          .get();
      
      if (existingDoc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Dipendente già esistente con username: $id'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      
      // Aggiungi il nuovo dipendente
      await FirebaseFirestore.instance.collection('dipendenti').doc(id).set({
        'nome': nome,
        'username': id,
        'attivo': true,
        'dataCreazione': FieldValue.serverTimestamp(),
      });

      _nomeController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Dipendente aggiunto!\nUsername: $id\nPassword: $EMPLOYEE_PASSWORD'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 5),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _toggleDipendente(String id, bool currentStatus) async {
    try {
      await FirebaseFirestore.instance.collection('dipendenti').doc(id).update({
        'attivo': !currentStatus,
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(currentStatus ? 'Dipendente disattivato' : 'Dipendente riattivato'),
          backgroundColor: Colors.blue,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _eliminaDipendente(String id, String nome) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Elimina Dipendente'),
        content: Text('Vuoi davvero eliminare $nome?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Elimina', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance.collection('dipendenti').doc(id).delete();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Dipendente eliminato'),
            backgroundColor: Colors.red,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore eliminazione: $e'),
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
        title: Text('Gestione Dipendenti'),
        backgroundColor: Colors.grey[900],
      ),
      body: Column(
        children: [
          // Form aggiungi dipendente
          Container(
            padding: EdgeInsets.all(16),
            color: Colors.grey[900],
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nomeController,
                    style: TextStyle(color: Colors.white),
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Nome Dipendente',
                      labelStyle: TextStyle(color: Colors.grey),
                      hintText: 'Es: Mario Rossi',
                      hintStyle: TextStyle(color: Colors.grey[600]),
                      border: OutlineInputBorder(),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.blue),
                      ),
                      prefixIcon: Icon(Icons.person_add, color: Colors.grey),
                    ),
                  ),
                ),
                SizedBox(width: 16),
                ElevatedButton(
                  onPressed: _aggiungiDipendente,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  ),
                  child: Text('Aggiungi', style: TextStyle(fontSize: 16)),
                ),
              ],
            ),
          ),
          
          // Info password
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(16),
            color: Colors.blue[900],
            child: Column(
              children: [
                Text(
                  'Password dipendenti:',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                Text(
                  EMPLOYEE_PASSWORD,
                  style: TextStyle(
                    color: Colors.white, 
                    fontSize: 20, 
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
          
          // Lista dipendenti
          Expanded(
            child: !firebaseInitialized
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cloud_off, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'Firebase non disponibile',
                          style: TextStyle(color: Colors.grey, fontSize: 18),
                        ),
                      ],
                    ),
                  )
                : StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('dipendenti')
                        .orderBy('nome')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.error, size: 64, color: Colors.red),
                              SizedBox(height: 16),
                              Text(
                                'Errore: ${snapshot.error}',
                                style: TextStyle(color: Colors.red),
                              ),
                            ],
                          ),
                        );
                      }

                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Center(
                          child: CircularProgressIndicator(),
                        );
                      }

                      final dipendenti = snapshot.data?.docs ?? [];

                      if (dipendenti.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.people_outline, size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text(
                                'Nessun dipendente registrato',
                                style: TextStyle(color: Colors.grey, fontSize: 18),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Aggiungi il primo dipendente usando il form sopra',
                                style: TextStyle(color: Colors.grey[600], fontSize: 14),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.builder(
                        padding: EdgeInsets.only(bottom: 16),
                        itemCount: dipendenti.length,
                        itemBuilder: (context, index) {
                          final doc = dipendenti[index];
                          final data = doc.data() as Map<String, dynamic>;
                          final isActive = data['attivo'] ?? false;

                          return Card(
                            margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            color: Colors.grey[850],
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isActive ? Colors.green : Colors.red,
                                child: Icon(
                                  Icons.person,
                                  color: Colors.white,
                                ),
                              ),
                              title: Text(
                                data['nome'] ?? 'Nome non disponibile',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Username: ${data['username'] ?? doc.id}',
                                    style: TextStyle(color: Colors.grey[400]),
                                  ),
                                  Text(
                                    isActive ? 'Attivo' : 'Disattivato',
                                    style: TextStyle(
                                      color: isActive ? Colors.green : Colors.red,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Switch(
                                    value: isActive,
                                    onChanged: (value) {
                                      _toggleDipendente(doc.id, isActive);
                                    },
                                    activeColor: Colors.green,
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete, color: Colors.red),
                                    onPressed: () {
                                      _eliminaDipendente(doc.id, data['nome'] ?? 'Dipendente');
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _nomeController.dispose();
    super.dispose();
  }
}