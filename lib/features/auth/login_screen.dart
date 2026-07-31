import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/bento_bandeja.dart';
import '../../core/theme/bento_cuadricula.dart';
import '../../core/theme/bento_icon.dart';
import '../../core/theme/bento_theme.dart';
import 'sesion_notifier.dart';

/// Ver docs/pantallas/flujo-descripcion.md#login--setup y
/// docs/pantallas/prototipos-ascii.md#login--setup.
/// Solo se ve la primera vez o tras cerrar sesion (cambio de rol en un
/// dispositivo compartido, no rutinario). La contrasena siempre existe
/// (de fabrica o ya cambiada desde Configuracion) — este flujo nunca
/// "crea" una contrasena, solo la pide.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  Rol? _rolSeleccionado;
  final _contrasenaController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _contrasenaController.dispose();
    super.dispose();
  }

  void _elegirRol(Rol rol) {
    setState(() {
      _rolSeleccionado = rol;
      _error = null;
    });
  }

  void _volver() {
    setState(() {
      _rolSeleccionado = null;
      _error = null;
      _contrasenaController.clear();
    });
  }

  Future<void> _entrar() async {
    final rol = _rolSeleccionado;
    if (rol == null) return;
    final ok = await ref
        .read(sesionNotifierProvider.notifier)
        .iniciarSesion(rol, _contrasenaController.text);
    if (!ok && mounted) {
      setState(() => _error = 'Contraseña incorrecta');
    }
  }

  @override
  Widget build(BuildContext context) {
    final laca = lacaDe(context);

    // El Login ES la bandeja, no una tarjeta flotando sobre ella.
    //
    // Antes era una columna de 480 dp centrada: en un teléfono pasaba, pero en
    // 1440 quedaba una cajita en el medio con la pantalla vacía alrededor — el
    // login web genérico. Y estaba pensado solo en vertical, así que acostado
    // con el teclado abierto se desbordaba 251 px.
    //
    // Ahora los compartimentos ocupan la bandeja completa hasta las esquinas, y
    // la elección de rol es literalmente eso: dos compartimentos del mismo peso.
    // Acostado y con el teclado abierto quedan ~230 dp de alto útil, y el
    // título se lleva 52 de ellos: el botón "Entrar" caía fuera de la vista y
    // había que desplazar para pulsarlo. Cuando el espacio aprieta, el título
    // es lo primero que sobra — la app ya se identificó al abrirse.
    final altoUtil = MediaQuery.sizeOf(context).height - MediaQuery.viewInsetsOf(context).bottom;
    final apretado = altoUtil < _altoConTitulo;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(BentoSpacing.rim),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!apretado) ...[
                // El título vive en la ESQUINA, sobre la bandeja, no centrado
                // como un encabezado de formulario. Lleva el color de texto de
                // bandeja explícito: con el de pozo (`onSurface`, casi negro en
                // modo claro) quedaba invisible sobre el marco oscuro — fue un
                // bug real.
                Text(
                  'VulpTiketing',
                  style: Theme.of(
                    context,
                  ).textTheme.headlineSmall?.copyWith(color: laca.textoEnBandeja),
                ),
                const SizedBox(height: BentoSpacing.pared),
              ],
              Expanded(child: _rolSeleccionado == null ? _elegirRolVista() : _contrasenaVista()),
            ],
          ),
        ),
      ),
    );
  }

  /// Dos compartimentos que llenan la bandeja: uno por rol, del mismo peso.
  ///
  /// Apilados en teléfono y lado a lado desde tablet. En vertical dos celdas
  /// altas y angostas se leerían como columnas, no como compartimentos.
  Widget _elegirRolVista() {
    final celdas = [
      BentoCelda(
        compacto: 6,
        medio: 3,
        amplio: 3,
        hijo: _TarjetaRol(
          rol: Rol.gerente,
          icono: 'rol_gerente',
          onTap: () => _elegirRol(Rol.gerente),
        ),
      ),
      BentoCelda(
        compacto: 6,
        medio: 3,
        amplio: 3,
        hijo: _TarjetaRol(
          rol: Rol.registradora,
          icono: 'rol_registradora',
          onTap: () => _elegirRol(Rol.registradora),
        ),
      ),
    ];

    // Mismo criterio que la vista de contraseña: apilado toma alto natural y se
    // desplaza; lado a lado llena la bandeja, con un piso para que la celda
    // nunca quede más baja que su contenido. Un teléfono acostado deja poco más
    // de 250 dp de alto, y sin piso la celda se aplastaba por debajo del icono.
    if (BentoAncho.de(context).esCompacto) {
      return SingleChildScrollView(child: BentoCuadricula(hijos: celdas));
    }
    return LayoutBuilder(
      builder: (context, restricciones) => SingleChildScrollView(
        child: SizedBox(
          height: math.max(restricciones.maxHeight, _altoMinimoRol),
          child: BentoCuadricula(llenarAlto: true, hijos: celdas),
        ),
      ),
    );
  }

  /// Lo que necesita una tarjeta de rol: icono de 48, separación, texto y el
  /// padding de celda grande.
  static const double _altoMinimoRol = 140;

  /// El rol elegido se queda donde estaba y la contraseña ocupa el resto.
  ///
  /// No es una pantalla nueva: es la misma bandeja con un compartimento que
  /// cede espacio. Por eso el rol sigue tocable — vuelve atrás.
  Widget _contrasenaVista() {
    final campo = BentoPozo(
      // El campo va DENTRO de un pozo: es contenido, y el contenido vive en
      // compartimentos, nunca suelto sobre el marco (DESIGN.md, regla 2).
      padding: const EdgeInsets.symmetric(
        horizontal: BentoSpacing.paddingCelda,
        vertical: BentoSpacing.unidad / 2,
      ),
      child: TextField(
        controller: _contrasenaController,
        obscureText: true,
        autofocus: true,
        decoration: InputDecoration(
          labelText: 'Contraseña',
          errorText: _error,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
        onSubmitted: (_) => _entrar(),
      ),
    );

    final acceso = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        campo,
        const SizedBox(height: BentoSpacing.pared),
        FilledButton(onPressed: _entrar, child: const Text('Entrar')),
        const SizedBox(height: BentoSpacing.unidad),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _volver,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Cambiar de rol'),
          ),
        ),
      ],
    );

    final celdas = [
      BentoCelda(
        compacto: 6,
        medio: 2,
        amplio: 2,
        hijo: _TarjetaRol(
          rol: _rolSeleccionado!,
          icono: _rolSeleccionado == Rol.gerente ? 'rol_gerente' : 'rol_registradora',
          seleccionada: true,
          onTap: _volver,
        ),
      ),
      BentoCelda(compacto: 6, medio: 4, amplio: 4, hijo: acceso),
    ];

    // Apilado (teléfono) cada celda toma su alto natural y la página se
    // desplaza. Repartir el alto disponible entre dos celdas apiladas era lo
    // que desbordaba con el teclado abierto: entre las dos necesitan más de lo
    // que queda, y ningún mínimo inventado acierta — el que puse primero se
    // quedaba 54 px corto.
    if (BentoAncho.de(context).esCompacto) {
      return SingleChildScrollView(child: BentoCuadricula(hijos: celdas));
    }

    // Lado a lado hay una sola fila, así que sí puede llenar el alto. El
    // `LayoutBuilder` da el alto REAL de la caja —dentro de un scroll es
    // infinito, y `llenarAlto` reparte con `Expanded`, que no reparte
    // infinitos— y ya viene descontado el teclado porque el `Scaffold` se
    // encoge solo.
    return LayoutBuilder(
      builder: (context, restricciones) => SingleChildScrollView(
        child: SizedBox(
          height: math.max(restricciones.maxHeight, _altoMinimoAcceso),
          child: BentoCuadricula(llenarAlto: true, hijos: celdas),
        ),
      ),
    );
  }

  /// Piso para la fila cuando el teclado deja muy poco: campo, botón y el
  /// enlace para cambiar de rol, en una sola fila.
  static const double _altoMinimoAcceso = 220;

  /// Alto útil a partir del cual cabe el título además del contenido.
  static const double _altoConTitulo = 320;
}

class _TarjetaRol extends StatelessWidget {
  const _TarjetaRol({
    required this.rol,
    required this.icono,
    required this.onTap,
    this.seleccionada = false,
  });

  final Rol rol;
  final String icono;
  final VoidCallback onTap;
  final bool seleccionada;

  @override
  Widget build(BuildContext context) {
    // Antes: `Card` rellena de `primaryContainer` al estar seleccionada, que
    // con la paleta de laca es un bloque de oro macizo — y el icono, que se
    // tinta con el mismo acento, quedaba oro sobre oro (invisible). Ahora la
    // seleccion se dice como en el resto del sistema: el compartimento
    // elegido es el que esta hundido, con la cresta en oro.
    return BentoPozo(
      onTap: onTap,
      seleccionado: seleccionada,
      padding: const EdgeInsets.all(BentoSpacing.paddingCeldaGrande),
      child: Column(
        // `min` y centrado: la celda puede ser más alta que su contenido —lo es
        // cuando llena la bandeja— pero el contenido no debe estirarse ni exigir
        // el alto completo. Con `max` reclamaba toda la altura y desbordaba 54 px
        // en cuanto el teclado apretaba la celda.
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          BentoIcon(icono, size: 48, activo: seleccionada),
          const SizedBox(height: BentoSpacing.unidad),
          Text(rol == Rol.gerente ? 'Gerente' : 'Registradora'),
        ],
      ),
    );
  }
}
