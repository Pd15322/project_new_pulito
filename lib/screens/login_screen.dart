import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../main.dart';

// Credenziali hardcoded
const String ADMIN_USERNAME = "paolo";
const String ADMIN_PASSWORD = "sdm16"; 
const String EMPLOYEE_PASSWORD = "sdm16"; 

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  Future<void> _login() async {
    setState(() => _isLoading = true);

    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      _showError('Inserisci username e password');
      setState(() => _isLoading = false);
      return;
    }

    // Verifica credenziali
    bool isValidLogin = false;
    bool isAdmin = false;

    if (username.toLowerCase() == ADMIN_USERNAME && password == ADMIN_PASSWORD) {
      // Login admin
      isValidLogin = true;
      isAdmin = true;
    } else if (password == EMPLOYEE_PASSWORD) {
      // Login dipendente con password condivisa
      // Verifica se il dipendente esiste nel database
      if (firebaseInitialized) {
        try {
          final employeeDoc = await FirebaseFirestore.instance
              .collection('dipendenti')
              .doc(username.toLowerCase())
              .get();
          
          if (employeeDoc.exists && employeeDoc.data()?['attivo'] == true) {
            isValidLogin = true;
            isAdmin = false;
          } else {
            _showError('Dipendente non trovato o non attivo');
            setState(() => _isLoading = false);
            return;
          }
        } catch (e) {
          print('Errore verifica dipendente: $e');
          // In caso di errore Firebase, permetti l'accesso locale
          isValidLogin = true;
          isAdmin = false;
        }
      } else {
        // Firebase offline, accetta qualsiasi username con password dipendenti
        isValidLogin = true;
        isAdmin = false;
      }
    } else {
      _showError('Credenziali non valide');
      setState(() => _isLoading = false);
      return;
    }

    if (isValidLogin) {
      // Salva lo stato di login
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', true);
      await prefs.setString('username', username);
      await prefs.setBool('isAdmin', isAdmin);

      // Naviga alla home
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => SchermataTavoli(username: username),
        ),
      );
    }

    setState(() => _isLoading = false);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo o titolo
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Text(
                  'SAPORI DI MARE',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              SizedBox(height: 50),
              
              // Form di login
              Container(
                width: double.infinity,
                constraints: BoxConstraints(maxWidth: 400),
                child: Card(
                  color: Colors.grey[900],
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        Text(
                          'Accesso',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 24),
                        
                        // Username
                        TextField(
                          controller: _usernameController,
                          style: TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Username',
                            labelStyle: TextStyle(color: Colors.grey),
                            prefixIcon: Icon(Icons.person, color: Colors.grey),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: Colors.blue),
                            ),
                          ),
                        ),
                        SizedBox(height: 16),
                        
                        // Password
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          style: TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            labelStyle: TextStyle(color: Colors.grey),
                            prefixIcon: Icon(Icons.lock, color: Colors.grey),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility : Icons.visibility_off,
                                color: Colors.grey,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: Colors.blue),
                            ),
                          ),
                          onSubmitted: (_) => _login(),
                        ),
                        SizedBox(height: 24),
                        
                        // Pulsante login
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: _isLoading
                                ? CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  )
                                : Text(
                                    'ACCEDI',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}