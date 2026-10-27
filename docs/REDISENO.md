# Rediseño: simulador de combate automático

Documento de trabajo del rediseño (fases 1 y 2): qué hay en el proyecto, qué se cambia y
cómo encaja todo. Se actualiza al terminar cada fase.

## 1. Auditoría (estado de partida, commit 24bccd4)

### Arquitectura
- Rojo: `src/server` (servicios que arranca `init.server.luau` con `safeStart`),
  `src/client` (controladores que arranca `init.client.luau`), `src/shared` (configuración y
  lógica pura que usan los dos). Un único DataStore (`SaveService`) y atributos del Player para
  replicar al cliente (`PlayerDataService.replicate`). Remotes con nombre en
  `Constants.Remotes` (los crea `RemoteService`).
- Pruebas fuera de Roblox: `python tests/run_tests.py <batería>` monta el código real de
  `src/` con un entorno simulado.

### Combate (antes del rediseño)
- **Dos caminos de disparo duplicados**, cada uno con su fórmula:
  - `CombatService`: un disparo por clic/F (cadencia 0.25 s), daño
    `CombatMath.playerDamage(LaserPower, mascotas) × 0.5`.
  - `PetCombatService`: tras el primer golpe, el servidor dispara solo un "PlayerLaser"
    cada 0.55 s (−0.022 s por nivel de Cadencia) con daño `6 + 4·LaserPower`, y las
    mascotas equipadas golpean al mismo objetivo cada 0.65 s.
- El limitador del servidor descarta disparos al mantener el clic (cuenta también los
  rechazados) y la mejora de Cadencia no afecta al disparo manual.
- Enemigos: una sola IA para todos (`EnemyService`, bucle cada 0.15 s) con estados Idle,
  Chase, Attack, Return y Dead. Jefes: golpe, golpe de área (Slam) y furia; antes de esta
  rama no se movían de su arena.

### Economía
- **Energía ⚡**: la producen los núcleos (`EnergyService`); paga la Resonancia del Cristal
  (`GeneratorPower`, requisito del renacimiento), huevos, zonas y núcleos.
- **Dinero 💰**: lo sueltan los enemigos (cada golpe y al morir); paga la Tienda de Láser.
- Ritmo medido con un jugador activo: ~700 💰/min en el Bosque con el láser inicial,
  ~2 500 en el Valle y ~7 000 en la Caldera.

### Huevos y mascotas
- Huevos: `EggConfig`, `EggLogic`, `PetService.purchaseEgg`, el jardín del mundo
  (`EggStandService`), el panel y la animación de incubar (`PetController`),
  `EggShrineAnimator`, `RevealGate`, el pase `TripleHatch`. Dependen de ellos: la diaria
  `DailyEggs`, el paso "Pet" del tutorial, el premio del día 7 y los códigos con `Pet`.
- Mascotas: `PetConfig` (24 especies, rarezas ×1.1 a ×6), `PetMath` (multiplicador aditivo),
  `PetService` (inventario, equipar, evolucionar, `grantPet`), `PetCombatService` (golpes de
  las equipadas), `PetFollower`/`PetModelBuilder` (cliente). El multiplicador sube la
  energía y la mitad de su bonificación el daño.
- Error encontrado: al cargar una partida, `SaveService.sanitize` partía de los datos vacíos,
  que ya traen la mascota inicial "p1", así que cada carga añadía otra y la equipaba primero.

### Mapas y progresión
- Bosque (por defecto) → Valle Morado (2 500 ⚡) → Caldera de Brasas (25 000 ⚡), unidos por
  portales de cristal (`ZoneService`); se cruza andando al desbloquear.
- Renacimiento: pide nivel de Resonancia `min(50, 15 + 5·n)`; da fichas y multiplicadores de
  energía, botín y daño; reinicia la energía y la Resonancia.
- Misiones, diarias y logros pagan energía; los premios diarios, cofres y códigos también.
- `GeneratorService` (santuario del cristal) y `CoreShrineService` (altares de núcleos) están
  desactivados en `init.server.luau`: no se tocan sin preguntar (ni cambiarían el mapa verde).

### Mapa verde (Bosque): objetos físicos que NO se modifican
Todo lo construye código al arrancar, en posiciones fijas:
- Terreno plano y suelo de bloques con sus caminos (`WorldService.buildFlatTerrain`,
  `StudWorld.buildFloor`, trazado en `StudFloor.Zones.Forest`).
- Muros del perímetro y la puerta (`StudWorld.buildWalls`), límite invisible
  (`LandscapeService`).
- Árboles, espantapájaros, calabazas, setas y hierba (`WorldService.buildForestDetails`, con
  semilla fija y círculos reservados: mover cualquier cosa reservada recoloca todo).
- Decoración de Navidad (`ChristmasDecor`, `SeasonConfig.ForestDecor`).
- Puestos del pueblo, evolucionador y cofre «RECLAMAR» (`VillageService`).
- Jardín de los huevos: altar, pedestales y expositor arcoíris (`EggStandService`).
- Tablas de clasificación (`LeaderboardService`), cofres escondidos (`ChestService`),
  portal (`ZoneService`), punto de aparición (`SpawnService`).
- Del archivo del lugar: `ReplicatedStorage.PetModels` (Haxigator) y los modelos sueltos
  que hay bajo el mapa.

Regla del rediseño: no se cambia ninguna posición, tamaño ni pieza de estos constructores
ni nada de lo que reserva sitio en el mapa. Lo nuevo reutiliza lo que ya existe (el
jardín de los huevos sigue igual, el puesto del láser es la Armería, las arenas de los
jefes siguen donde están).

## 2. Arquitectura del rediseño

### Monedas
(Actualizado en la fase 1 del rediseño de pelea: ver la sección 5.)

| Moneda | Se gana | Se gasta |
|---|---|---|
| 💰 Dinero | Enemigos, oleadas, cofres, premio diario, códigos, aventuras | Armas, guantes, bastones y sus mejoras, huevos, zonas, mejoras de la Armería |
| 💎 Diamantes | Enemigos (pocos), oleadas, jefes, misiones, diarias, logros, tienda | Habilidades de los estilos, Velocidad de Correr, núcleos |
| 🔄 Fichas | Renacer | Tienda de fichas |

Las mascotas multiplican el daño (50 % de su bonificación) y el dinero (50 %).

### Armas (fase 3)
- `WeaponConfig` + `WeaponLogic` (puras) y `WeaponService` (servidor). Siete armas con daño,
  cadencia, alcance, proyectil y efecto propios (área, salto entre enemigos, ralentizar):
  Láser Básico, Bláster de Plasma, Arco de Espinas (jefe del Bosque), Cañón Cristalino
  (Valle), Prisma de Amatista (jefe del Valle), Cañón del Vacío (Caldera), Corazón de Magma
  (jefe de la Caldera).
- Cada arma tiene niveles (+15 % de daño por nivel, hasta 25). La antigua "Potencia del
  Láser" pasa a ser el nivel del Láser Básico. La Cadencia es global (todas las armas).
- La Armería es el puesto "Mejorar Láser" del pueblo (mismo sitio y modelo; cambia su
  nombre) y también se abre con la tecla L o el botón del menú.
- Panel con el diseño «Armería Roblox» (`WeaponController`): cabecera naranja a rayas,
  una tarjeta por arma (cuatro a la vista, flechas para el resto) con rareza, colores,
  números y botones (comprar, equipar, mejorar). Plasma, Cañón Cristalino y Cañón del Vacío
  también se compran con Robux (`MonetizationConfig.WeaponProducts`, `ShopService`; llegan
  aunque su zona siga cerrada). Las mejoras globales de la Armería (Cadencia, Poder de
  Mascotas, Velocidad) se quitaron del panel por ahora: siguen en el servidor y en el
  guardado, pero no se pueden comprar. El arte de cada arma (`WeaponConfig.Art`) y el
  icono de la cabecera (`WeaponConfig.ArmoryArt.Header`) son las imágenes del diseño,
  subidas a Roblox (Prisma, Vacío, Magma y el icono con el borde difuminado como en el
  diseño). Sin imagen, la tarjeta muestra el icono del arma.
- Precios con el ritmo real: Plasma 4 000 (~6 min en el Bosque), Cañón Cristalino 25 000
  (~10 min en el Valle), Cañón del Vacío 120 000 (~15 min en la Caldera).

### Disparo (fase 5) y pase "Disparo automático"
- Un único camino de disparo en el servidor (`PetCombatService`), con la cadencia y el
  efecto del arma equipada. Las mascotas atacan al mismo objetivo.
- Sin el pase, el arma dispara solo cuando el jugador lo pide (`Attack`, validado en
  `CombatService`): un clic o toque en un enemigo le dispara a él; F, X (mando) o el botón
  "Disparar", al más cercano a tiro. Cada petición es un disparo (espera la recarga del arma,
  pero caduca); mantener pulsado repite la petición cada 0.15 s.
- Con el pase (`MonetizationConfig.GamePasses.AutoFire`, Id 0 hasta crearlo), el arma
  dispara sola al enemigo más cercano a tiro. La insignia del botón (AUTO / OFF, o la tecla
  V) lo apaga y lo enciende; sin el pase muestra "🔒 AUTO" y abre la tienda.

### Mascotas y huevos (la fase 4 se deshizo)
- El jardín de los huevos vuelve a estar como antes del rediseño: se compran e incuban
  huevos con energía (`EggConfig`, `EggLogic`, `PetService.purchaseEgg`, `EggStandService`),
  con el panel de huevos, la diaria `DailyEggs` y el pase `TripleHatch`.
- Los jefes ya no regalan mascotas: dan su arma y energía (`BossRewardService`).
- Se conserva de la fase 4 el arreglo de la mascota inicial duplicada al cargar
  (`SaveService.sanitize`).
- El Haxigator se sigue vendiendo por Robux en el altar.

### Jefes (fase 6)
- Máquina de estados propia (`EnemyService.updateBoss`): Patrulla, Persecución (con
  `PathfindingService` si algo se interpone), Ocupado (ataque anunciado), Descanso y Regreso.
  Nunca salen de su territorio; mantienen el objetivo unos segundos.
- Identidad: Guardián del Bosque (golpe de área + raíces que ralentizan), Coloso de Amatista
  (golpe de área + embestidas), Titán de la Caldera (golpe de área + saltos + bolas de fuego).

### Progresión entre mapas (fase 7)
- Valle: derrotar al Guardián del Bosque + 2 500 ⚡. Caldera: derrotar al Coloso + 25 000 ⚡.
- Los jefes derrotados se guardan (`Bosses`); quien ya tenía una zona la conserva.

### Renacimiento
- (Fase 1 del rediseño de pelea) Ya no hay Resonancia: renacer queda bloqueado
  («Próximamente», `RebirthConfig.Enabled = false`) hasta que la fase 2 elija el requisito
  nuevo. Se reinicia: dinero y niveles de las armas. Se conserva: 💎, armas compradas y la
  equipada, mascotas, zonas, jefes derrotados, mejoras de la Armería, núcleos, misiones y la
  tienda de fichas.

### Guardado
- Esquema v8: `Weapons` (`WeaponLogic.serialize`) y `Bosses`. Los registros antiguos cargan
  con el láser inicial (con el nivel de la antigua Potencia del Láser) y sin jefes.

## 3. Estado de la implementación (fases 3 a 8)

| Fase | Commit | Qué quedó hecho |
|---|---|---|
| 3. Armas y Armería | f9df766 | `WeaponConfig`/`WeaponLogic`/`WeaponService`, `BossRewardService`, `PlayerDataService.combatStats`, guardado v8, Armería (puesto, tecla L, botón "Armas") |
| 4. Mascotas sin huevos | cc84b9a | Jardín = tienda de mascotas fijas (`PetLogic`, `BuyPet`, `PetStandDisplay`), mascotas de jefe, premio del día 7 fijo, tutorial nuevo, arreglo de la mascota inicial duplicada |
| 5. Combate automático | ae05d96 | Un solo camino de disparo (`PetCombatService`), clic = elegir objetivo, F/botón = AUTO/OFF, proyectil por arma, arreglo del arranque de `EnemyService` |
| 6. IA de jefes | e094955 | `EnemyService.updateBoss` (patrulla, persecución con rutas, ataques anunciados, descanso, regreso), aviso "¡Te persigue!" |
| 7. Progresión de mapas | 9795eef | `RequiredBoss` por zona, `BossesDefeated`, panel del portal y cartel de la puerta |
| 8. Interfaz y guardado | 2df0941 | Mascotas suman la mitad de su bonificación al dinero (`CombatConfig.PetMoneyShare`), panel de mascotas con sus tres bonificaciones, baterías de guardado reparadas y ampliadas |
| Huevos y pase de disparo | (sin commit) | Vuelve el jardín de los huevos (se deshace la fase 4, menos el arreglo de la mascota inicial); disparo a mano (clic, F, mantener) y automático solo con el pase `AutoFire` |

### Mapa verde
Comprobado con `git diff 24bccd4`: no cambió ningún constructor de geometría (terreno, suelo,
caminos, muros, árboles y decoración, Navidad, cofres, aparición, tablas, posiciones de
enemigos y arenas). Solo cambia el nombre flotante del puesto del láser ("Armería"); el
jardín de los huevos vuelve a ser el de antes, con los pedestales más abiertos hacia los
lados (a petición, para no apretarse con el altar): No común y Raro 4 studs, Común y el
Arcoíris 5. Siguen sobre el suelo rosa, dentro del terreno que el mapa deja libre y sin
tocar nada.

### Pruebas automáticas (`python tests/run_tests.py`)
Pasan 18 de 24 baterías. Nuevas o reparadas en el rediseño: `weapons` (34), `petcombat`
(disparo a mano y automático con el pase, 27), `persist` (38, con dinero, armas y jefes al
salir y volver), `persist_cores`, `core_service`, `tutorial`, `sandbox`, `shop` (79, con los
huevos), `rebirth`, `adventure`. Las 6 que fallan ya fallaban en el punto de partida por
motivos ajenos al rediseño (`sanctuary` 1, `shrines` 2, `quest` 1, `landscape` 16, `zones`
9: la Caldera ya no pide 3 renacimientos y no hay portales de vuelta, `leaderboard` 1).

### Pendientes conocidos
- `GeneratorService` (santuario del cristal) y `CoreShrineService` (altares de núcleos) siguen
  desactivados: el aviso "Renacer" del cristal no aparece (renacer funciona con la tecla T).
- Las pruebas con varios jugadores a la vez solo están cubiertas por código y por las
  baterías (estado por jugador, reparto de recompensas por daño); falta probarlo en Studio
  con 2 jugadores (Test > Players).
- El guardado real no se puede probar en Studio sin "Enable Studio Access to API Services";
  está cubierto por la batería `persist` sobre un DataStore simulado.
- Imágenes y mallas: todo lo que se ve en el juego está subido a Roblox (rbxassetid). Las
  mallas de los huevos, la textura arcoíris y los iconos del menú estaban como archivos
  locales en la carpeta de Studio (rbxasset://…): se perdían al actualizarse Studio y los
  jugadores no los veían. Ahora vienen de `EggConfig.Art` (importadas de huevos.glb) e
  `Icons.Ids`. No volver a usar archivos copiados en la carpeta de Studio.
- Los Ids de Robux (pases, también "Disparo automático", productos y Haxigator) siguen en 0:
  hasta crearlos, la tienda los muestra como "Próximamente" y nadie tiene el automático.

## 4. Pruebas obligatorias (fase 9)

"Studio" = comprobado en Play en Roblox Studio; "batería" = prueba automática
(`tests/run_tests.py`); "código" = solo revisión de código.

| # | Escenario | Resultado | Cómo |
|---|---|---|---|
| 1 | Jugador nuevo entra al mapa verde | ✅ | Studio: láser equipado, "🔒 AUTO" (sin el pase), mascota inicial, tutorial activo |
| 2 | El mapa conserva geometría y distribución | ✅ | `git diff 24bccd4`: ningún constructor de geometría cambió (ver sección 3) |
| 3 | Ataca a un enemigo (a mano; solo con el pase) | ✅ | Studio: sin el pase no dispara solo (vida 20 → 20); F = un disparo, mantener = ráfaga a la cadencia; con el pase mata solo (155 → 350 💰 en 4 s); batería `petcombat` |
| 4 | El enemigo recibe daño válido y muere | ✅ | Studio y batería `petcombat` (muerte única de EnemyLogic) |
| 5 | Recompensa correcta | ✅ | Studio: 35 💰 · 1.375 (mascotas) = 48 por Espinillo |
| 6 | Compra un arma y la equipa | ✅ | Studio: Plasma (4 000) y Cañón Cristalino (25 000, con el Valle); batería `weapons` |
| 7 | Daño y cadencia del arma equipada | ✅ | Studio: Cañón Cristalino 0.45 s entre disparos y 122 💥/s; batería `petcombat` |
| 8 | Bonificaciones de las mascotas | ✅ | Studio: el Zorrito de Cuarzo sube daño y dinero (×1.375); batería `weapons` |
| 9 | Huevos como antes del rediseño | ✅ | Studio: Huevo del Bosque por 50 ⚡ → Seta Saltarina equipada; baterías `shop`, `rebirth`, `zones` |
| 10 | Las mascotas guardadas no se pierden | ✅ | Baterías `persist`, `persist_cores`, `rebirth` (y arreglo de la inicial duplicada) |
| 11 | El jefe detecta al jugador | ✅ | Studio: estado Chase y TargetUserId al acercarse |
| 12 | Persigue y evita obstáculos | ✅ | Studio: rodeó un muro de prueba con la ruta de PathfindingService |
| 13 | Ataca solo cuando corresponde | ✅ | Studio: ciclo Busy → Recover → Chase con avisos en el suelo |
| 14 | El jugador puede escapar | ✅ | Studio: a 90 studs deja de perseguir |
| 15 | Regresa a su territorio | ✅ | Studio: vuelve a Patrol junto al centro de su arena |
| 16 | Recompensas una sola vez | ✅ | Studio: arma y energía una vez; el segundo golpe no hace nada |
| 17 | El siguiente mapa sigue bloqueado | ✅ | Studio: con 50 000 ⚡, BossLocked; tras el Guardián, Success; batería `zones` |
| 18 | El progreso se conserva al volver | ✅ batería | `persist`: dinero, armas, equipada, niveles y jefes. En Studio no se puede (DataStore sin acceso a la API) |
| 19 | Sin botones rotos ni errores | ✅ | Studio: los 9 paneles se abren y cierran; 0 errores en cliente y servidor |
| 20 | Varios jugadores a la vez | ⚠️ código | Estado por jugador, reparto por daño y premios por jugador; falta una prueba con 2 jugadores en Studio |

## 5. Rediseño de pelea, fase 1: sin ⚡ energía ni cristal

El juego pasa a ser de pelea (estilos, armas, oleadas, mazmorras y jefes). Las únicas
monedas son 💰, 💎 y 🔄 fichas. Se quitó:
- La **Resonancia del Cristal** (mejora `GeneratorPower`), el santuario del cristal
  (`GeneratorService`, `GeneratorAnimator`, `CrystalAppearance`) y el Círculo Elemental
  (`CoreShrineService`, `CoreShrineController`, `CoreShrineConfig`). De `GeneratorConfig`
  solo quedan `Position` (origen del mapa) y `TerrainFillOffset`; los sitios que reservaban
  los altares pasan a `WorldConfig.AltarReserve` para que el reparto del bosque no cambie.
- La **producción** por segundo y la **recompensa offline** (`ProductionPerSecond`,
  `CoreLogic` producción/afinidad/offline, `EconomyConfig.PassiveEnergy`). Los núcleos se
  despiertan y suben con 💎 y solo dan sus habilidades (Q/R); Naturaleza no tiene nivel.
  `EnergyService` solo suma 💎 (`grant`) y avisa una vez por segundo a misiones y tutorial.
- Del renacimiento: el requisito de Resonancia (queda «Próximamente» hasta la fase 2) y las
  ventajas «Inicio rápido» y «Sueño profundo».

Lo que dependía del "poder de energía" ahora usa valores de Config:

| Qué | Antes | Ahora |
|---|---|---|
| 💎 por enemigo y de las oleadas | · poder de diamantes (Resonancia, núcleos, mascotas…) | · `PlayerDataService.diamondMultiplier` (pase ×2, poción, amuletos, bendición) |
| Premio diario, cofres, códigos | minutos de producción | minutos de `ZoneConfig.Zones.*.MoneyPerMinute` de la mejor zona abierta |
| Misiones, diarias, logros (💎) | coste de la siguiente Resonancia / 30 | Min · `QuestConfig.ZoneFactor` de la mejor zona, con Max |
| Aventuras (💰) | coste de la siguiente Resonancia | Min · `AdventureConfig.ZoneMoneyFactor` de la zona del personaje, con Max |
| Amuletos Savia/Magma, Bendición de Abundancia | poder del cristal | +25 % / +50 % / ×2 de 💎 |
| Pase «Mejora automática» (`AutoUpgrade`) | subía la Resonancia | mejora con 💰 el arma del estilo actual |
| Pase «Diamantes ×2» (`DoubleEnergy`) | ×2 de poder (también offline) | ×2 de 💎 |
| Mascotas | 100 % a la energía, 50 % daño, 50 % 💰 | 50 % daño, 50 % 💰 |
| Misiones del cristal | «Despierta el cristal», «Pulir el cristal», «Resonancia plena» | «Mejora tu arma», «Afila tu arma» (evento `WeaponUpgraded`), «Maestro armero» (mismos ids) |
| Renacer | Resonancia 15 + 5·n | bloqueado («Próximamente») hasta la fase 2 |
