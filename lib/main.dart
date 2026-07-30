import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/crypto/cifrado_nativo.dart';

void main() {
  // `cryptography_flutter` se registra solo al inicializar el binding; esto
  // solo deja en el log cuál implementación de cifrado quedó activa, para poder
  // distinguir "el backup tarda" de "el backup cayó al cifrado lento".
  WidgetsFlutterBinding.ensureInitialized();
  reportarCifrado();

  runApp(const ProviderScope(child: VulpTiketingApp()));
}
