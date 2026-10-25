# Pruebas automáticas

Se ejecutan **fuera de Roblox** con el intérprete de [Luau](https://github.com/luau-lang/luau).
Rojo no incluye esta carpeta en el juego: `default.project.json` solo sincroniza
`src/shared`, `src/server` y `src/client`.

## Ejecutar

```bash
python tests/run_tests.py            # todas las baterías actuales
python tests/run_tests.py quest tutorial
python tests/run_tests.py --legacy   # además, las heredadas (ver abajo)
```

Hace falta Python 3 y el ejecutable de Luau (`luau.exe` en Windows). Cópialo en
`tools/luau/` (carpeta ignorada por git) o indica su carpeta con la variable de entorno
`LUAU_BIN`.

## Cómo funcionan

`run_tests.py` **monta** cada batería en `tests/.build/` (ignorada por git):

1. un entorno simulado de Roblox (`harness/`),
2. los módulos **reales** de `src/`, sustituyendo cada `require(...)` por el módulo
   incrustado,
3. el cuerpo de la prueba (`suites/`).

Así cada ejecución prueba el código actual. Ninguna batería accede a DataStores reales:
las de guardado usan un DataStore simulado en memoria.

| Batería | Qué comprueba |
|---|---|
| `sanctuary` | Santuario del Núcleo Cósmico: contrato de nombres, colisiones, zonas libres del mapa, flotación, órbitas sin cruces, animación |
| `shrines` | Círculo Elemental (altares de los núcleos): contrato con el cliente, estado dormido, colisiones, respeto del mapa (huevos, camino, árboles, enemigos) y alturas |
| `sandbox`, `sandbox_early` | Modo prueba del tutorial: ninguna llamada al DataStore, perfil temporal, nunca se guarda |
| `tutorial` | Pasos, omitir, veteranos, carga fallida, dos jugadores |
| `persist` | Guardado y carga de energía y mejoras, fallos de carga y de guardado, perfiles antiguos |
| `quest` | Misiones, diarias y logros: reclamar una sola vez, reinicio diario, validación; diarias de mejorar el cristal y abrir huevos (avisos de `GameEvents`, solo la Resonancia cuenta) |
| `combat` | Daño, muerte única, reparto de recompensas, objetivos |
| `petcombat` | Habilidades de mascotas |
| `anim` | Animación de enemigos |
| `pose` | Articulaciones de los modelos de enemigos |
| `cores` | Núcleos: configuración y lógica pura (costes, producción, afinidad, offline) |
| `persist_cores` | Guardado v3 de los núcleos: migración, correcciones archivadas, vuelta atrás a v2 |
| `core_service` | Núcleos fase 2: despertar, mejorar, elegir (afinidad), cobro, atributos, guardado y producción offline al cargar |
| `abilities` | Habilidades elementales: configuración de los 8 elementos, fórmulas (maestría, cadena, jefes), estados de control, segundo elemento (Q + R), recarga por elemento, combos (marcas, reacciones, Remolino) y AbilityService (objetivos, curación, quemadura, velocidad, retroceso, oleadas, remote) |
| `rebirth` | Renacimiento: requisito, reinicio en el mismo paso, fichas y tienda, multiplicadores (producción, offline, botín, daño), espacios de mascota, huevos ya desbloqueados, guardado y aviso social |
| `landscape` | Paisaje: azar determinista, caminos, faroles, bosque y decoración fuera de las zonas de juego, lo construido a mano, límite invisible y montañas; jardines de huevos (santuarios dentro, separados y mirando al centro, mobiliario sin estorbar, entrada libre y conectada, zona segura); personajes de las aventuras y objetos perdidos en sitios despejados; pueblo (casas, plaza y puestos sin solaparse, calle hasta el portal, zona segura); naturaleza del norte (río fuera de las zonas de enemigos, caminos que solo cruzan el agua por el puente, piedras de la cascada a saltos cortos, praderas y lomas fuera de las zonas de juego) y cofres en sitios despejados |
| `adventure` | Aventuras: configuración (5 historias de 3 misiones; la 2.ª ranura de amuleto sigue pidiendo las 4 primeras), saneado, aceptar / progreso / entregar (derrotas, objetos perdidos y entregas entre personajes), amuletos y ranuras, bendiciones (activar, alargar, tope y caducidad), pasivas (producción, offline, daño, botín, velocidad) y AdventureService real (distancias, recogida al pasar, límites de frecuencia, guardado v5 y registros v4) |
| `zones` | Zonas: desbloqueo con energía y renacimientos (la Caldera pide 3, sin cobrar si faltan, NaN cuenta como 0), zonas separadas, portales de ida y de vuelta, enemigos fuera de zonas seguras, huevos y mascotas de cada zona, aventuras y misiones que solo nombran zonas que existen, volcán y lago de lava de la Caldera |
| `leaderboard` | Monolitos de clasificación: orden por valor, desempate (renacimientos por energía generada, luego nombre), valores no válidos ignorados, tope de filas, páginas (servidor, global y semana) bien definidas y sitios libres junto al spawn |
| `hudlayout` | Interfaz: menú agrupado, columnas, tarjetas, botones de combate y pila de avisos sin solaparse ni salirse en muchas pantallas de escritorio y táctiles; con un panel abierto los avisos bajan, se ponen a su lado o esperan (nunca encima del panel) |
| `world` | Mundo vivo: ciclo de día y noche (horas de cada tramo, sin saltos, día más largo que la noche, luz de luna, Caldera fija), cofres escondidos (saneado del guardado, abrir y esperar, reloj adelantado, estado para el cliente, premios que existen) y cauce del río (cortes, ancho, de la poza de la cascada al lago) |
| `shop` | Premio diario y códigos (racha, día perdido, reloj atrasado, códigos caducados o con renacimientos, límite de intentos, premios concedidos y guardados), tienda (pases desde Roblox y comprados en la partida, Energía ×2 también offline, Más mascotas que quita las de más si no se tiene, recibos que no se conceden dos veces y que solo se confirman guardados, mejora automática con su interruptor), huevos ×3 todo o nada, mascota de regalo, mejor huevo, la semana de la clasificación y los cofres escondidos de verdad (energía y bendición, espera guardada al momento, sin abrir dos veces, estado al cliente) |
| `energy` | Energía solo de matar (`PassiveEnergy = false`): sin producción por segundo ni offline, `EnergyService.grant` suma al momento y cuenta como generada una vez por ciclo, cantidades raras rechazadas, se guarda |
| `waves` | Oleadas: arenas coherentes con zonas, jefes y enemigos, reserva para cada tipo, cada oleada más dura, orden de aparición, dificultad y premios, mejoras (ofrecer, elegir, tope, efectos), racha (ventana, Racha larga, multiplicador), orbe dorado y energía de cada enemigo |
| `items` | Inventario (`ItemLogic`): configuración coherente con jefes y huevos, datos guardados saneados (v8 sin inventario, cantidades, tope, títulos), el tiempo de las pociones solo corre jugando, tomar/sumar/tope/acabarse, huevos guardados, botín de los jefes y títulos (conceder, ponerse solos, elegir a mano) |

## Pruebas heredadas (`legacy/`)

`pettest`, `eggtest`, `zonetest`, `savetest`, `layouttest` y `stagetest` llevan dentro
**copias antiguas** de los módulos que probaban. Se conservan como referencia, pero **no
validan el código actual**. Para recuperarlas hay que separar su cuerpo en `suites/` y
montarlas desde `src/` como las demás.

## Modo prueba del tutorial (Studio)

`src/server/DevConfig.luau` se guarda en git con `TutorialSandbox = false`. Para probar
el tutorial desde cero sin tocar tu partida real:

1. Cambia `TutorialSandbox = false` por `true` (con `rojo serve` conectado se sincroniza).
2. Pulsa **Play** en Studio: verás el aviso «🧪 Modo prueba del tutorial».
3. Al terminar, vuelve a dejarlo en `false`. `run_tests.py` avisa si se ha quedado en `true`.

En una partida publicada se ignora siempre (`RunService:IsStudio()` es falso).
