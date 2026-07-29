# 0021 — Paquete de mDNS para sync: `bonsoir`

**Fecha:** 2026-07-28
**Estado:** Aceptada

## Contexto

`DeviceDiscoveryService` (0019) necesita **anunciar** el rol activo de este dispositivo y **descubrir** pares visibles en la red local, funcionando en los tres targets del proyecto: Android, Linux, Windows (Architecture.feature). Se investigaron tres candidatos vía sus páginas de pub.dev antes de comprometerse (no se asumió compatibilidad sin verificar).

## Investigación

| Paquete | Android | iOS/macOS | Linux | Windows | Anunciar | Descubrir |
|---------|---------|-----------|-------|---------|----------|-----------|
| `nsd` | ✅ | ✅ | ❌ **no soportado** | ✅ | ✅ | ✅ |
| `multicast_dns` | ✅ | ✅ | ✅ | ✅ | ❌ **solo consulta, no responde/anuncia** | ✅ |
| `bonsoir` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

- `nsd` queda descartado de inmediato: no tiene implementación para Linux, uno de nuestros tres targets obligatorios.
- `multicast_dns` (el paquete oficial de `dart-lang`) solo expone `MDnsClient` para hacer *lookup* de registros existentes (`PtrResourceRecord`, `SrvResourceRecord`) — no tiene forma de anunciar/responder por un servicio propio. Serviría si solo necesitáramos descubrir, pero necesitamos ambas direcciones.
- `bonsoir` es el único que cubre los tres targets **y** ambas operaciones (`broadcast your own` + `discover network services`, basado en Bonjour/Android NSD, con `bonsoir_linux`/`bonsoir_windows`/`bonsoir_android` como implementaciones nativas por plataforma).

## Decisión

Usar `bonsoir` para `DeviceDiscoveryService`.

## Hallazgo importante — `bonsoir_linux` depende de `avahi-daemon`

`bonsoir_linux` se implementa sobre D-Bus (dependencia `dbus: ^0.7.12`), lo que en la práctica significa que habla con **`avahi-daemon`** del sistema operativo — no reimplementa mDNS desde cero en Linux. Esto es una dependencia de **sistema operativo**, no solo de paquete Dart: si `avahi-daemon` no está instalado o no está corriendo en el dispositivo Linux, la sync simplemente no vería otros dispositivos en esa máquina.

Verificado en este entorno de desarrollo (CachyOS): `avahi-daemon` está instalado y activo (`systemctl is-active avahi-daemon` → `active`). La mayoría de distros de escritorio (GNOME, KDE, etc.) lo traen habilitado por defecto porque lo usan para impresoras de red y compartir archivos — pero **no es una garantía universal** en instalaciones mínimas o servidores.

**Consecuencia práctica:** la app debe tratar la ausencia de sync como un caso normal, no un error fatal — esto ya estaba cubierto por 0007 ("la sync nunca es requisito para operar: toda la app funciona 100% offline"), pero ahora hay una causa concreta más para que sync no esté disponible en un dispositivo dado (además de "no hay otros dispositivos en la red"): que Avahi no esté corriendo. `SyncNotifier` debería poder distinguir/loggear esto para diagnóstico, aunque de cara al usuario el resultado visible es el mismo ("sin sincronizar").

## Alternativas descartadas

- `nsd` — sin soporte Linux.
- `multicast_dns` — sin capacidad de anunciar, solo de descubrir.
- Implementar mDNS a mano (sockets UDP crudos + parseo de paquetes DNS) — muchísimo más trabajo y superficie de bugs que usar una librería ya mantenida para algo tan estándar; sin ninguna necesidad especial que lo justifique.

## Consecuencias

- `pubspec.yaml` agrega `bonsoir`.
- `DeviceDiscoveryService` dice de que reciba una implementación real basada en `BonsoirBroadcast`/`BonsoirDiscovery` — la interfaz abstracta ya definida en 0019 no cambia.
- Documentar en las notas de instalación/despliegue (a futuro, cuando exista una guía de instalación) que Linux necesita `avahi-daemon` activo para que la sync funcione.
