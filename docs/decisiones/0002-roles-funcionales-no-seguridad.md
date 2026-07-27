# 0002 — Roles como separación funcional, no de seguridad interna

**Fecha:** 2026-07-26
**Estado:** Aceptada

## Contexto

Authentication.feature y Operations.feature definen permisos distintos para Gerente y Registradora. Cabía la duda de si esto modela un control de seguridad estricto entre usuarios internos.

## Decisión

La separación de roles es funcional/de interfaz: cada rol ve la UI relevante a su trabajo (POS simple vs. control completo). El propósito real de pedir credenciales es evitar que **terceros ajenos al negocio** accedan a los datos si el dispositivo cae en otras manos — no proteger datos de la Registradora frente al Gerente ni viceversa.

Además, se agregará una opción en configuración para cambiar la contraseña de la app en el dispositivo específico (almacenamiento local, no sincronizado como credencial).

## Consecuencias

- El diseño de permisos no necesita ser a prueba de un adversario interno malicioso.
- La contraseña de cada dispositivo es independiente — no hay noción de "cuenta" centralizada de usuario.
- Ver [seguridad](../arquitectura/seguridad.md) para el modelo de amenaza completo.
