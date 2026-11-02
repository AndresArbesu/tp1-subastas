# Cuestionario teórico — Casa de Subastas

## 1. Procesos y memoria aislada

¿Qué es un proceso en Elixir? ¿Qué significa que los procesos tengan memoria aislada y cómo intercambian información?

Un proceso en Elixir es una unidad de ejecución que corre en la máquina virtual de Erlang, BEAM. Cada proceso mantiene su propia memoria aislada del resto de los procesos: no puede modificar directamente el estado de otro. Además, cuenta con su propio PID y con un mailbox que utiliza para recibir mensajes. Los procesos intercambian información mediante el envío y la recepción de mensajes.

## 2. Concurrencia y paralelismo

¿Cuál es la diferencia entre concurrencia y paralelismo? ¿Puede haber concurrencia aunque sólo se disponga de un núcleo de procesamiento?

El paralelismo es la ejecución simultánea de actividades. La concurrencia significa que varias actividades están en progreso durante períodos que se superponen. Pueden avanzar alternándose en un mismo núcleo o ejecutándose en paralelo si hay varios núcleos disponibles.

Puede haber concurrencia en un mismo núcleo de procesamiento porque mientras se ejecutan instrucciones de un proceso, las de otro esperan, y la planificación alterna su ejecución. Por eso, la concurrencia no requiere paralelismo, aunque ambos pueden ocurrir juntos.

## 3. Condiciones de carrera

¿Qué es una condición de carrera (race condition)? ¿Por qué comprobar un dato y modificarlo en dos operaciones separadas puede producir resultados incorrectos cuando hay varios participantes?

Una race condition aparece cuando el resultado depende del orden en que se intercalan operaciones concurrentes y esa falta de coordinación puede producir un resultado incorrecto. No requiere que los procesos compartan memoria; también puede ocurrir en un protocolo basado en mensajes.

Comprobar y modificar un dato por separado deja una ventana en la que otro participante puede cambiar la condición. Así, la modificación podría basarse en una comprobación que ya no es válida.

## 4. Un único dueño del estado

¿Cómo ayuda que un único proceso administre un estado y atienda los pedidos de a uno a evitar condiciones de carrera? ¿Por qué usar procesos y mensajes no elimina automáticamente todos los problemas de concurrencia?

Mediante la serialización se consigue que los pedidos sean atendidos de a uno a la vez. Si un único proceso es dueño del estado y realiza la comprobación y la actualización dentro de la misma atención, otro pedido no puede intercalarse entre esas dos acciones y cambiar la condición que se comprobó.

Esto no elimina necesariamente todos los problemas de concurrencia, ya que podría ocurrir que no toda la lógica de una operación quede contenida en un mismo pedido. Por ejemplo, si una operación lógica se divide en varios pedidos, entre ellos podría haber cambios de estado debidos a otros participantes que afecten el resultado final. Es decir, usar procesos y mensajes no garantiza por sí solo que el protocolo en general conserve la consistencia del estado.

## 5. Orden de los mensajes

¿Qué garantías de orden ofrece Elixir para los mensajes enviados por un mismo proceso a otro? ¿Qué puede ocurrir cuando varios procesos envían mensajes al mismo destinatario?

Cuando un proceso envía varios mensajes a otro, se garantiza que lleguen en el orden en que ese mismo emisor los envió a ese destinatario. Sin embargo, no necesariamente se procesan en ese orden: un `receive` selectivo puede dejar pendiente un mensaje anterior y seleccionar uno posterior que coincida con alguno de sus patrones.

Cuando varios procesos envían mensajes al mismo destinatario, no hay un orden global garantizado entre los distintos emisores. Cuál llega primero depende de la planificación y del momento del envío, aunque se conserva el orden de los mensajes de cada emisor.

## 6. Mailbox y receive

¿Qué es el mailbox de un proceso y cómo selecciona mensajes un receive? ¿Qué ocurre con los mensajes que no coinciden con sus patrones?

El mailbox de un proceso es una cola que recibe mensajes para ser procesados. Cuando se ejecuta `receive`, se recorre la cola desde el inicio y se busca el primer mensaje que coincida con alguno de los patrones definidos. Si un mensaje no coincide, se saltea y se examina el siguiente. Cuando hay coincidencia, se remueve el mensaje de la cola y se ejecuta la rama correspondiente.

Los mensajes que no coinciden se quedan esperando. Si no encuentra ningún mensaje que coincida, el proceso queda esperando uno que sí coincida, o hasta que venza el timeout si se especificó un `after`.

## 7. Sobrecarga de un mailbox

¿Qué riesgos aparecen si un mailbox recibe mensajes más rápido de lo que el proceso puede atenderlos? Considerá el consumo de memoria, el tiempo de respuesta y el costo de buscar mensajes entre muchos pendientes. ¿Qué estrategias generales pueden reducir estos riesgos?

Si llegan mensajes más rápido de lo que el proceso puede atenderlos, se acumulan en el mailbox y aumenta el consumo de memoria. También crece el tiempo de respuesta, porque los pedidos quedan pendientes durante más tiempo. Si el `receive` busca un patrón específico, puede tener que recorrer muchos mensajes que no coinciden, aumentando el costo de búsqueda.

Para mitigar esto se puede limitar la cantidad de solicitudes pendientes, esperar confirmaciones de disponibilidad antes de enviar más mensajes o rechazar pedidos si no hay capacidad. También se puede optimizar el procesamiento de los mensajes o distribuir el trabajo entre procesos independientes, cuando el diseño lo permita.

## 8. Timeouts y reintentos

¿Qué indica un tiempo de espera agotado (timeout) al esperar una respuesta? ¿Por qué no implica necesariamente que la operación haya sido cancelada? ¿Qué problemas pueden generar las respuestas tardías y los reintentos?

Un cliente puede enviar un pedido y dejar de esperar después de un plazo. Esa decisión ocurre en el cliente. El destinatario puede no haber comenzado, estar trabajando, haber terminado sin que la respuesta llegue todavía o haber terminado y dejado la respuesta pendiente. Un timeout no permite distinguir por sí solo esos casos.

Dejar de esperar no elimina el pedido del mailbox del destinatario ni interrumpe o revierte una operación que ya comenzó.

Los reintentos de operaciones no idempotentes podrían duplicar su efecto si se interpretan como solicitudes nuevas. Las respuestas tardías también pueden confundirse con una espera posterior si el patrón es demasiado amplio.

## 9. Envío asincrónico

¿Qué significa que el envío de mensajes en Elixir sea asincrónico? ¿Qué diferencia hay entre enviar un mensaje, que el destinatario lo reciba y que termine de procesarlo?

El envío es asincrónico porque el proceso emisor puede continuar su ejecución sin esperar a que el destinatario procese el mensaje o le responda. Enviar, recibir y procesar son momentos distintos; que el envío haya retornado no confirma que la operación se haya realizado.

Primero se realiza un `send(pid, message)` para enviar un pedido desde un proceso. Si el destinatario sigue vivo y el mensaje llega, queda en su mailbox. Si coincide con alguno de los patrones de un `receive`, el destinatario lo selecciona, lo retira del mailbox y ejecuta la rama correspondiente. Si no coincide, permanece pendiente.

## 10. Terminación de procesos

¿Qué ocurre con el estado y los mensajes pendientes de un proceso cuando termina? ¿Cómo puede otro proceso enterarse de su terminación y por qué sería útil conocerla?

Cuando un proceso termina, se pierde su estado local y se descartan los mensajes que quedaron pendientes en su mailbox.

Otro proceso puede monitorearlo mediante `Process.monitor(pid)` y recibir un mensaje `:DOWN` con la referencia del monitor, el PID y el motivo de terminación. Esto sirve para detectar que ya no está disponible y decidir cómo actuar, por ejemplo informar un error, dejar de esperar una respuesta o eliminarlo de un registro.
