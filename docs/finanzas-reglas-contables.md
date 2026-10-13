# Reglas contables de Finanzas (Krezium)

Este documento es la referencia obligatoria de las reglas de integridad de saldos
del módulo Finanzas. Las Tasks de la Fase 01 implementan exactamente estas
reglas; si una Task descubre una contradicción entre este documento y la
spec o el código existente, **se corrige aquí primero**, antes de tocar
lógica o UI.

## 1. Qué suma y qué resta saldo

- [ ] Una transacción de tipo `ingreso` **suma** su `monto` al saldo de su
      `accountId`.
- [ ] Una transacción de tipo `gasto` **resta** su `monto` al saldo de su
      `accountId`.
- [ ] Una transacción es una transferencia cuando `tipo == 'transferencia'`
      (no por tener `transferToAccountId` no nulo — ese campo puede ser
      nulo en una transferencia histórica, ver sección 7). Siendo
      transferencia, **resta** su `monto` de la cuenta origen (`accountId`)
      y, si tiene destino, **suma** el mismo `monto` a la cuenta destino
      (`transferToAccountId`).
- [ ] Si `accountId == transferToAccountId` (autotransferencia), el efecto
      sobre esa cuenta es **cero**: no resta ni suma. Es un caso real de
      corrupción de datos históricos (ver auditoría de Fase 01), no solo
      una posibilidad teórica inalcanzable desde la UI.
- [ ] Las reservas (`FinanceReservations`) **no afectan** el saldo contable
      de la cuenta; son un apartado informativo sobre el saldo ya existente
      (ver sección 4, "disponible estimado").
- [ ] `saldoInicial` de `FinanceAccounts` es el punto de partida del saldo
      agregado (sección 2); no es una transacción y no aparece en el
      historial de movimientos.

## 2. Cómo se calcula el saldo agregado de una cuenta

- [ ] `saldo(cuenta) = saldoInicial(cuenta) + Σ ingresos(cuenta) − Σ gastos(cuenta)
      + Σ transferencias_entrantes(cuenta) − Σ transferencias_salientes(cuenta)`.
- [ ] Solo se incluyen transacciones **no archivadas**; las archivadas se
      excluyen del cálculo (ver sección 5).
- [ ] El saldo total de todas las cuentas activas es la suma de
      `saldo(cuenta)` para cada cuenta con `activa = true`. Las cuentas
      inactivas (`activa = false`) no participan en el total agregado, pero
      conservan su propio saldo calculable individualmente.

## 3. Transferencias: tratamiento en origen y destino

- [ ] Una transferencia es **un solo registro** en `FinanceTransactions`
      (no dos filas): `accountId` es el origen, `transferToAccountId` es el
      destino.
- [ ] En el origen, la transferencia se trata como salida de dinero (resta).
- [ ] En el destino, la transferencia se trata como entrada de dinero
      (suma), usando el mismo `monto` (no hay conversión de moneda ni
      comisión implícita en este modelo).
- [ ] Si se edita el `monto` o alguna de las dos cuentas de una
      transferencia existente, el recálculo de saldo debe reflejar
      correctamente el cambio en ambas cuentas (la anterior y la nueva, si
      cambiaron).

## 4. Disponible estimado

- [ ] `disponible_estimado(cuenta) = saldo(cuenta) − Σ monto de reservas
      activas de esa cuenta`.
- [ ] El disponible estimado puede ser negativo (ver sección 6); eso no
      bloquea operaciones, es solo información para el usuario.
- [ ] El disponible estimado nunca se usa como el saldo real de la cuenta;
      es una cifra derivada, de solo lectura, calculada on-the-fly.

## 5. Archivar o eliminar un registro

- [ ] Esta fase solo archiva **cuentas** (`FinanceAccounts.activa`). No
      existe el concepto de "transacción archivada" ni "categoría
      archivada": una transacción vive o se elimina físicamente, y una
      categoría está presente o no lo está.
- [ ] Eliminar una transacción (borrado físico) recalcula el saldo de la(s)
      cuenta(s) afectada(s) como si esa transacción nunca hubiera existido.
- [ ] `deleteFinanceAccountSafely` rehúsa eliminar una cuenta que aún tenga
      transacciones o reservas asociadas (lanza una excepción); la UI debe
      ofrecer archivar en su lugar.
- [ ] `deleteFinanceAccountAndHistory` sí permite el borrado físico
      definitivo de una cuenta aunque tenga transacciones o reservas —
      borra también ese historial dentro de la misma transacción — pero
      solo tras una confirmación explícita del usuario. No es cierto que
      una cuenta con transacciones nunca pueda eliminarse.
- [ ] Eliminar una cuenta que es destino de transferencias (`transferToAccountId`)
      no está restringido por ese lado: el FK usa `onDelete: setNull`, es
      decir, la transferencia queda "histórica sin destino" (ver sección 7)
      en vez de bloquear el borrado.

## 6. Una reserva que excede el saldo

- [ ] El sistema **permite** crear o mantener una reserva cuyo `monto`
      exceda el saldo actual de la cuenta; no hay validación que lo bloquee.
- [ ] El efecto es que `disponible_estimado` (sección 4) puede quedar en
      negativo. Esto es una señal informativa para el usuario, no un error
      de integridad de datos.

## 7. Transferencia histórica sin destino

- [ ] Una transacción con `tipo == 'transferencia'` y `transferToAccountId
      = null` (p. ej. porque la cuenta destino fue eliminada y el FK aplicó
      `setNull`) se trata, para efectos de cálculo de saldo, por la misma
      rama de transferencia que cualquier otra: solo afecta el origen
      (resta su `monto`), porque no hay destino al que acreditar. No se
      trata como un ingreso/gasto genérico de "su tipo" — su `tipo` sigue
      siendo `'transferencia'`.
- [ ] Una autotransferencia (`accountId == transferToAccountId`) tiene
      efecto cero sobre esa cuenta (ver sección 1) — no se cuenta como
      salida de dinero.
- [ ] Esta transacción no debe causar errores ni excepciones en los
      cálculos de saldo agregado; el campo `transferToAccountId` nulo es un
      estado válido y esperado, no una condición de error.
- [ ] El campo `revisionNota` (`FinanceTransactions.revisionNota`, nullable)
      existe para que, en tareas futuras, el sistema o el usuario puedan
      dejar constancia de que una transferencia quedó en este estado
      histórico sin destino (p. ej. al detectarlo durante un recálculo o
      una migración), sin necesitar una tabla adicional ni perder el
      registro original.
