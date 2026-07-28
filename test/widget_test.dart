import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vulp_tiketing/app.dart';

void main() {
  testWidgets('La app arranca en Login sin sesion activa', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: VulpTiketingApp()));
    await tester.pump();

    expect(find.text('VulpTiketing'), findsOneWidget);
    expect(find.text('Gerente'), findsOneWidget);
    expect(find.text('Registradora'), findsOneWidget);
  });
}
