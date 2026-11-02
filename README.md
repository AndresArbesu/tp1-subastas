# Casa de Subastas

TP1 — Taller de Programación I — FIUBA.

## Autor

- Nombre y apellido: Andrés Ezequiel Arbesú
- Padrón: 102155

## Requisitos y preparación

Versiones utilizadas: **Elixir 1.20.5** y **Erlang/OTP 29**. El proyecto declara Elixir `~> 1.20` y no utiliza dependencias externas.

Se requieren Git y Elixir con una versión compatible de Erlang/OTP. Mix se incluye con Elixir. Si no están instalados, consultar la [guía oficial de instalación](https://elixir-lang.org/install.html).

Desde una clonación limpia:

```bash
git clone https://github.com/AndresArbesu/tp1-subastas.git
cd tp1-subastas
mix compile
```

No hace falta ejecutar `mix deps.get`.

## Ejecutar la CLI

```bash
mix run -e 'CLI.start()'
```

Todas las operaciones siguientes se realizan dentro de una misma ejecución. Para salir, usar `exit`.

| Comando | Operación |
| --- | --- |
| `help` | Mostrar ayuda. |
| `active` | Listar subastas activas, con ID, producto y mayor oferta o indicación de que no hay ofertas. |
| `create "PRODUCT" INITIAL_PRICE DURATION_MS` | Crear una subasta. Precio y duración deben ser enteros positivos; duración en milisegundos. |
| `show AUCTION_ID` | Consultar el estado de una subasta, incluso después del cierre. |
| `bid AUCTION_ID USER AMOUNT` | Ofertar un importe entero positivo, superior a la referencia vigente. |
| `exit` | Terminar la CLI. |

Usar comillas para productos o usuarios con espacios. El producto y el usuario no pueden estar vacíos.

## Ejemplo y guion reproducible de CLI

Ejecutar desde una sesión nueva. Los comandos iniciales deben completarse antes de que venza la primera subasta. Su duración es de 60 segundos.

```text
> help
Commands:
  help
  active
  create "PRODUCT" INITIAL_PRICE DURATION_MS
  show AUCTION_ID
  bid AUCTION_ID USER AMOUNT
  exit

> create "Keyboard" 1000 60000
Created auction 1.
> active
1 | Keyboard | no bids
> bid 1 ana 1200
Bid accepted.
> bid 1 bruno 1200
Error: {:bid_too_low, 1200}
> bid 1 bruno 1500
Bid accepted.
> show 1
Auction: %{
  id: 1,
  status: :active,
  result: nil,
  highest_bid: %{user: "bruno", amount: 1500},
  product_name: "Keyboard",
  initial_price: 1000,
  accepted_bids_count: 2,
  expires_at: -576460691772,
  duration_ms: 60000
}
> show 999
Error: :auction_not_found
> create "Monitor" 5000 0
Error: :invalid_duration
> create "Monitor" abc 10000
Error: price and duration must be integers.
> unknown
Unknown command. Type help.
> active
1 | Keyboard | 1500 by bruno
```

Las salidas corresponden a una ejecución real. El orden de los campos del mapa puede variar y `expires_at` cambia entre ejecuciones porque usa tiempo monotónico. Su valor puede ser negativo.

Esperar a que transcurran los 60 segundos desde la creación de Keyboard y continuar en la misma sesión:

```text
> show 1
Auction: %{
  id: 1,
  status: :closed,
  result: %{final_price: 1500, winner: "bruno"},
  highest_bid: %{user: "bruno", amount: 1500},
  product_name: "Keyboard",
  initial_price: 1000,
  accepted_bids_count: 2,
  expires_at: -576460691772,
  duration_ms: 60000
}
> bid 1 carla 2000
Error: :auction_closed
> active
No active auctions.
> create "No bids" 1000 1000
Created auction 2.
```

Esperar más de un segundo desde esta última creación:

```text
> show 2
Auction: %{
  id: 2,
  status: :closed,
  result: %{final_price: nil, winner: nil},
  highest_bid: nil,
  product_name: "No bids",
  initial_price: 1000,
  accepted_bids_count: 0,
  expires_at: -576460690517,
  duration_ms: 1000
}
> exit
```

Este guion permite comprobar las operaciones y que la CLI continúa funcionando después de informar errores.

## Tests y formato

```bash
mix test
mix format --check-formatted
mix format --check-formatted scripts/simulation.exs
```

Los tests con ExUnit cubren creación y consulta de subastas, validación de datos, identificadores únicos y operaciones sobre subastas inexistentes. Para las ofertas se comprueban la aceptación, el rechazo de importes insuficientes y la conservación del estado ante rechazos. También se verifica el cierre automático con y sin ofertas, el ganador y precio final, el rechazo después del vencimiento y la inmutabilidad del resultado cerrado.

Las pruebas concurrentes coordinan varios procesos emisores y contrastan sus respuestas con el estado de la subasta: ante ofertas iguales se acepta exactamente una; ante ofertas distintas se conserva el máximo enviado y el contador coincide con las aceptaciones. Además, se comprueba que varias subastas mantengan sus ofertas, resultados y vencimientos independientes. Las esperas están acotadas y los procesos creados por los tests se limpian al finalizar.

## Simulación de 100 usuarios

```bash
mix run scripts/simulation.exs
```

El script crea tres subastas y coordina 100 procesos de usuario. Cada usuario consulta las subastas y realiza ofertas iniciales; los mismos procesos vuelven a ofertar después del vencimiento. Se incluyen ofertas iguales e insuficientes.

Se verifican las respuestas, los conteos de aceptaciones, la mayor oferta, el resultado final y la inmutabilidad del estado tras las ofertas tardías. El script muestra los resultados por subasta y termina con `Simulation passed` si las verificaciones pasan; ante una discrepancia o un timeout detectado termina con error.

Las cantidades de aceptaciones y rechazos por importe pueden variar según el orden de atención. En este escenario, la mayor oferta enviada por subasta es 2100, de `user_100`. La simulación no utiliza azar.

## Diseño

### Procesos y responsabilidades

El sistema se organiza principalmente en dos tipos de procesos: un proceso administrador y un proceso independiente por cada subasta.

El administrador se encarga de crear las subastas, asignarles identificadores únicos durante la ejecución y mantener un registro que relaciona cada identificador con el PID correspondiente. Este registro, junto con la interfaz de AuctionClient, permite abstraer los PIDs de las subastas, de modo que el cliente opera mediante identificadores públicos sin tener que conocer ni administrar los PIDs. El administrador no almacena el estado interno de las subastas ni interviene en la aceptación o el rechazo de ofertas.

Cada proceso de subasta es el único dueño de su estado: producto, precio inicial, vencimiento, mayor oferta con su usuario, contador de ofertas aceptadas y resultado. Se encarga de responder consultas, aceptar o rechazar ofertas y cerrar la subasta al vencer el plazo, independientemente de las demás subastas. Después del cierre permanece disponible para consultar su resultado.

El módulo AuctionClient ofrece las operaciones por identificador público y encapsula la localización y la comunicación con los procesos correspondientes. Sus funciones se ejecutan en el proceso del cliente. El módulo no constituye un proceso adicional. Para consultar u ofertar, primero obtiene del administrador el PID asociado al identificador y luego se comunica directamente con la subasta. La CLI interpreta los comandos ingresados y muestra las respuestas.


### Estado y ofertas concurrentes

Cada proceso de subasta atiende un pedido por vez. La validación de una oferta y la actualización del estado se realizan dentro de la misma atención, evitando que otro pedido se intercale entre ambas acciones. Una oferta aceptada actualiza conjuntamente el importe, el usuario y el contador. Una oferta rechazada no modifica los datos de las ofertas.

No se supone un orden de atención entre distintos emisores. Entre ofertas iguales que superan la referencia vigente, sólo la primera atendida puede aceptarse. Si una oferta mayor se atiende antes que otra menor, la menor se rechaza. Distintas subastas mantienen estados propios y pueden avanzar de forma independiente.


### Vencimiento y cierre

Al inicializar una subasta se calcula su vencimiento con tiempo monotónico, antes de confirmar la creación, y se programa un temporizador para el cierre automático. Este reloj permite medir el plazo sin depender de cambios en la hora del sistema.

Además del temporizador, se comprueba el vencimiento al comenzar a atender consultas y ofertas. Si el plazo ya se alcanzó, primero se cierra la subasta. Las ofertas se rechazan y las consultas muestran el estado cerrado, aunque el mensaje del temporizador todavía estuviera pendiente. Por eso, enviar una oferta antes del vencimiento no garantiza su aceptación. Lo que importa es cuándo la subasta comienza a procesarla.

Al cerrar, se establece como resultado el usuario y el importe de la mayor oferta aceptada. Si no hubo ofertas, no hay ganador ni precio final. El proceso permanece vivo para responder consultas y rechazar nuevas ofertas, sin modificar el resultado.

### Limitaciones conocidas

La limitación principal es la centralización de la creación y el descubrimiento de subastas en el proceso administrador. Aunque las ofertas se envían directamente a cada subasta una vez resuelto su identificador, esa búsqueda pasa por un único proceso y podría convertirse en un cuello de botella ante un volumen elevado de solicitudes.

Otra decisión de diseño es mantener vivos los procesos de las subastas cerradas para conservar su estado y permitir consultas posteriores. Esto simplifica la implementación, pero hace que la cantidad de procesos y el uso de memoria crezcan con las subastas creadas durante la ejecución. Como alternativa, se podrían persistir los resultados o transferirlos a un proceso recolector antes de terminar cada subasta. Un recolector permitiría reducir la cantidad de procesos vivos, aunque seguiría acumulando los resultados en memoria y requeriría coordinar su transferencia y las consultas.

Tampoco se limita explícitamente la cantidad de mensajes pendientes. Si llegan pedidos más rápido de lo que un proceso puede atenderlos, pueden aumentar el consumo de memoria y los tiempos de respuesta. Además, un timeout no garantiza que la operación haya sido cancelada y no se implementa deduplicación de reintentos.

El listado de subastas activas consulta cada subasta por separado, por lo que no representa una instantánea simultánea del sistema. No se ofrecen garantías de tiempo real, aunque las demoras de planificación no extienden el plazo de aceptación de ofertas.

Por último, los datos se mantienen únicamente en memoria, como permite la consigna. No hay persistencia ni recuperación automática del estado ante la terminación inesperada de un proceso.

## Cuestionario

Las respuestas individuales están en [`cuestionario.md`](cuestionario.md).

