# Cuestionario teórico — Casa de Subastas

## 1. Procesos y memoria aislada

¿Qué es un proceso en Elixir? ¿Qué significa que los procesos tengan memoria aislada y cómo intercambian información?

Un proceso en Elixir es uan unidad de ejecución que corre en la máquina virtual de erlang, BEAM. Cada proceso mantiene su propia memoria aislada del resto de procesos. Además cuenta con su propio PID y con una casilla de mailbox que utliza para comunicación con otros procesos.  

## 2. Concurrencia y paralelismo

¿Cuál es la diferencia entre concurrencia y paralelismo? ¿Puede haber concurrencia aunque sólo se disponga de un núcleo de procesamiento?

El paralelismo es la ejecución simultanea entre procesos. En la concurrencia los procesos se alternan y su ejecución no es simultánea. A pesar de que "avancen" en paralelo, en realidad se alternan coordinadamente. Esto puede pasar en un mismo núcleo de procesamiento porque mientras se ejecutan instrucciones de un proceso, las del otro esperan.

## 3. Condiciones de carrera

¿Qué es una condición de carrera (race condition)? ¿Por qué comprobar un dato y modificarlo en dos operaciones separadas puede producir resultados incorrectos cuando hay varios participantes?

Una race condition es un problema que aparece cuando varios procesos trabajan sobre los mismos datos en memoria descoordinadamente. Comprobar y modificar un dato por separado deja una ventana en la que otro participante puede cambiar la condición. 

## 4. Un único dueño del estado

¿Cómo ayuda que un único proceso administre un estado y atienda los pedidos de a uno a evitar condiciones de carrera? ¿Por qué usar procesos y mensajes no elimina automáticamente todos los problemas de concurrencia?

Mediante la serialización se consigue que los pedidos sean administrados de a uno a la vez, evitando condiciones de carrera por pedidos en simultáneo. Todos los pedidos pasan a la "misma cola" de atención. 
Esto no elimina todos los problemas de concurrencia necesariamente ya que podrían exitir otros problemas relacionados a que no toda la lógica de la ejecución quede contenida en un mismo pedido. Por ejemplo, si un proceso ejecutase una transacción de forma partida, entre operaciones podrían haber cambio de estados debidos a la concurrencia, que afectan el resultado final. Es decir, usar procesos y mensajes no garantiza por sí solo que el protocolo en general conserve la consistencia del estado.

## 5. Orden de los mensajes

¿Qué garantías de orden ofrece Elixir para los mensajes enviados por un mismo proceso a otro? ¿Qué puede ocurrir cuando varios procesos envían mensajes al mismo destinatario?

Cuando un proceso envía varios mensajes a otro, se garantiza el orden de la secuencia enviada originalmente de ese mismo emisor en ese destinatario. Pero no se garantiza procesamiento en orden, eso depende de que si el receive encuentra un patrón en el mensaje que matchee o no. 

Cuando varios procesos envían mensajes al mismo destinatario, no hay un orden global garantizado entre los distintos emisores. Cuál llega primero depende de la planificación y del momento del envío, aunque se conserva el orden de los mensajes de cada emisor.

## 6. Mailbox y receive

¿Qué es el mailbox de un proceso y cómo selecciona mensajes un receive? ¿Qué ocurre con los mensajes que no coinciden con sus patrones?

El mailbox de un proceso es una cola que recibe mensajes para ser procesados. Cuando se ejecuta receive se recorre desde el inicio en la cola y se fija que coincida con alguno de los patrones definidos. Si no, se saltea y se agarra el siguiente. Cuando hay coincidencia, se remueve el mensaje de la cola y se ejecuta la rama correspondiente. 

Los mensajes que no coinciden se quedan esperando. Si no encuentra ningún mensaje que coincida, el proceso queda esperando uno que sí coincida, o hasta que venza el timeout si se especificó un after.


## 7. Sobrecarga de un mailbox

¿Qué riesgos aparecen si un mailbox recibe mensajes más rápido de lo que el proceso puede atenderlos? Considerá el consumo de memoria, el tiempo de respuesta y el costo de buscar mensajes entre muchos pendientes. ¿Qué estrategias generales pueden reducir estos riesgos?

Si llegan mensajes más rápido de lo que el proceso puede atenderlos, se acumulan en el mailbox y aumentaría el consumo de memoria. También crece el tiempo de respuesta, porque los pedidos quedan pendientes durante más tiempo. Si el receive busca un patrón específico, puede tener que recorrer muchos mensajes que no coinciden, aumentando el costo de búsqueda.

Para mitigar esto se puede limitar la cantidad de solicitudes pendientes, esperar confirmaciones de disponibilidad antes de enviar mensajes o rechazar pedidos si no lo hay. En otro orden, optimizar el procesamiento de los mensajes o distrubuirlos. 

## 8. Timeouts y reintentos

¿Qué indica un tiempo de espera agotado (timeout) al esperar una respuesta? ¿Por qué no implica necesariamente que la operación haya sido cancelada? ¿Qué problemas pueden generar las respuestas tardías y los reintentos?

Un cliente puede enviar un pedido y dejar de esperar después de un plazo. Esa decisión ocurre en el cliente. El destinatario puede no haber comenzado, estar trabajando, haber terminado sin que la respuesta llegue todavía o haber terminado y dejado la respuesta pendiente. Un timeout no permite distinguir por sí solo esos casos.

Los reintentos podrían generar problemas de idempotencia al ser interpretados como solicitudes nuevas y duplicar su efecto. Las respuestas tardías también pueden confundirse con una espera posterior si el patrón es demasiado amplio. 


## 9. Envío asincrónico

¿Qué significa que el envío de mensajes en Elixir sea asincrónico? ¿Qué diferencia hay entre enviar un mensaje, que el destinatario lo reciba y que termine de procesarlo?

El término asincróico en este contexto significa principalmente que hay tres momentos que no ocurren necesariamente seguidos. El envío del mensaje, la llegada al destinatario y el procesamiento del mensaje. Cada uno ocurre de acuerdo a distintos eventos y no hay garantía de sincronicidad entre ellos. 

En el primero, se realiza un `send(pid, message)` para enviar un pedido desde un proceso. Luego, en algún momento el destinatario lo recibirá y agregará a su cola de pedidos. Y por último, el destinatario lo procesará en la cola, asumiendo que habrá coincidencia. 

## 10. Terminación de procesos

¿Qué ocurre con el estado y los mensajes pendientes de un proceso cuando termina? ¿Cómo puede otro proceso enterarse de su terminación y por qué sería útil conocerla?

