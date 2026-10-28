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
- (Fase 2 del rediseño de pelea) Requisito: ganar las oleadas del modo que toca desde el
  último renacimiento (ver sección 6) y tener 💰 (×3 por renacimiento hasta el 5.º, ×1,5 después). Se reinicia: dinero y niveles
  de las armas. Se conserva: 💎, armas compradas y la equipada, mascotas, zonas, jefes
  derrotados, mejoras de la Armería, núcleos, misiones y la tienda de fichas.

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
  `DiamondService` (antes `EnergyService`) solo suma 💎 (`grant`) y avisa una vez por segundo a misiones y tutorial.
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

**Guardado v16** (`SaveService.refundRetired`): al cargar se devuelve el 100 % del 💰 que
costó la Resonancia (Σ floor(60 · 1,45ⁿ) por nivel; nivel 15 ≈ 💰 35 000) y las fichas de
«Inicio rápido» y «Sueño profundo»; las tres se borran del registro, así que no se cobran dos
veces, y el jugador ve un aviso (atributo `RetiredRefund`). Mascotas, armas, zonas, jefes,
núcleos, clases, habilidades, misiones, inventario y 💎 se quedan igual.

**Guardado v17** (renombrado): en el código, los atributos y el guardado los 💎 se llaman
`Diamonds` (antes `Energy`): `profile.Diamonds`, atributo `Diamonds`, `TotalDiamonds`,
`DiamondService`, `DiamondsEarned`, misiones `EarnDiamonds`/`DailyDiamonds`, poción `Diamonds`,
`Weekly.Diamonds`, código `InsufficientDiamonds`. Al cargar, un registro anterior a la v17 usa
su `Energy` (y los nombres viejos de las misiones, la poción y la semana); al guardar se borra
`Energy`. No cambian: el id del pase `DoubleEnergy`, el DataStore `RC_Global_Diamonds_v1` ni
las piezas "Energy" de los portales (son geometría del mapa).

## 6. Rediseño de pelea, fase 2: renacimiento nuevo

Elegido: **oleadas + 💰** y reiniciar solo 💰 y el nivel de las armas.

| Renacimiento | Oleadas (desde el último renacimiento) | 💰 |
|---|---|---|
| 1 | Ganar las Oleadas del Guardián (Bosque, 10) | 25 000 |
| 2 | Oleadas del Coloso (Valle) | 75 000 |
| 3 | Oleadas del Titán (Caldera) | 225 000 |
| 4 | Oleadas del Gólem de Hielo (Tundra) | 675 000 |
| 5 | Oleadas del Equilibrio (Tierras Divididas) | 2 025 000 |
| 6 | Tierras Divididas en el modo infinito: 3 oleadas más | 3 037 500 |
| 7, 8… | Tierras Divididas en el modo infinito: 3 oleadas más cada vez | ×1,5 cada vez (4 556 250, 6 834 375…) |

- `RebirthConfig.Requirement` (Waves, EndlessExtraWaves, MoneyBase, MoneyGrowth ×3 hasta el
  5.º renacimiento, LateGrowthFrom = 6 y LateMoneyGrowth ×1,5 desde el 6.º).
- `RebirthLogic.requirement / progress / recordWave / canRebirth / rebirth(data, money, now)`;
  códigos `WavesNotDone` e `InsufficientMoney` (con el progreso para el cliente).
- `Rebirth.Cycle` (oleada más alta de cada modo desde el último renacimiento): lo anota
  `RebirthService.recordWave` con el evento `WaveCleared` de `WaveService`, se replica en el
  atributo `RebirthCycle` y se vacía al renacer. Los registros antiguos empiezan con el ciclo
  vacío (las victorias de antes no cuentan para el próximo renacimiento).
- Panel (`RebirthController`): requisito con ✅, barra (mitad oleadas, mitad 💰) y botón que
  dice qué falta.

## 7. Correcciones de las pruebas con amigos, bloque 1: ritmo, economía y clases

Lo que dijeron: "en 1 hora me pasé casi todo", "las gemas están infladas: mejoré al máximo
todas las clases jugando solo con el Guerrero", "la regeneración de vida es muy alta", "la
velocidad de correr es excesiva", "el Guerrero no tiene desventajas", "los Puños son
inferiores al Guerrero" y "el mago genera maná muy rápido y tiene la misma vida".

### 💎 diamantes (la causa principal)
Los 💎 de cada bicho eran `Reward · 3 %`, y el `Reward` (💰) se multiplica por ~5 en cada
zona: en el Mundo 2 cada bicho daba cientos de 💎. Además los jefes daban 60…4 000 y cada
partida ganada, `40 · RewardScale` (hasta ×60). Una partida de la Caldera daba ~8 900 💎;
una clase entera de un estilo (comprar las 4 y subirlas) cuesta ~8 600.

Ahora (valores en Config, prueba "Ritmo de los 💎" en la batería `waves`):

| Fuente | Antes | Ahora |
|---|---|---|
| Cada bicho | `Reward · 0.03` | `KillDiamonds` (pequeño 0.025, mediano 0.15) · `DiamondTier` de su zona · ×3 si es élite |
| Cada oleada | `1 · w · RewardScale` | `0.06 · w · DiamondTier` |
| Victoria | `40 · RewardScale` | `2 · DiamondTier` |
| Jefes (`DiamondReward`) | 60 / 150 / 400 / 1 000 / 3 000 / 4 000 ×2 | 3 / 6 / 12 / 20 / 30 / 25 ×2 |
| Misiones, diarias, logros | Min · factor, con tope | lo mismo · `QuestConfig.RewardScale` (0,2) |

`DiamondTier`: Bosque 1, Valle 1,6, Caldera 2,5, Tundra 3,5, Fortaleza 4,5, Mundo 2 5 y
Tierras Divididas 5,5 (el 💰 de esas zonas va ×1 … ×3 000).

💎 por partida ganada (sin pases): Bosque ~13, Valle ~28, Caldera ~65, Tundra ~119, Oleadas
del Equilibrio ~131 y Oleadas Gemelas ~171 (antes ~430, ~1 900, ~8 900, ~38 000 y
~118 000). Con partidas de 6 a 15 min son ~130-680 💎 por hora: la 2.ª clase (200 💎) cuesta
~1,5 h en el Bosque y una clase entera de un estilo, decenas de horas. Los pases y pociones
de 💎 siguen multiplicando (pagar acelera, no regala). Las habilidades del Mundo 2 bajan de
1 500 / 3 000 / 6 000 / 12 000 a 600 / 1 200 / 2 000 / 3 500 💎 para que se puedan alcanzar.

### 💰 y zonas
Precio de las puertas: Valle 25 000 (antes 12 500), Caldera 250 000 (125 000), Tundra
1 500 000 (600 000), Fortaleza 6 000 000 (3 500 000) y Tierras Divididas 15 000 000
(20 000 000). Con el 💰 de una partida ganada (Bosque ~5 600, Valle ~25 000, Caldera
~110 000, Tundra ~460 000) son unas 4, 10, 13 y 13 partidas de la zona anterior.

### Vida, velocidad y estilos
- Regeneración: `HealthService` quita la de Roblox (1 %/s siempre) y cura 0,5 %/s solo tras
  6 s sin recibir daño (`CombatConfig.Regen`). Al limpiar una oleada, 20 % (antes 35 %).
- Velocidad de Correr: +1 por nivel hasta 10 (antes +2,5 hasta 20); los niveles guardados de
  más cuentan como 10.
- Guerrero (el de las hordas): ×1,2 de daño (1,35), recibe ×0,95 (0,85), camina ×0,95
  (1,05), ×1,25 de vida (1,3), el bloqueo deja pasar el 45 % (30 %) y -15 % a los jefes.
- Puños (el de los jefes): ×1,6 de daño (1,5) y +35 % a los jefes (`StyleConfig` BossDamage,
  `StyleLogic.bossDamage`, aplicado en `StyleService`).
- Magia: -20 % de vida (`MaxHealth` 0,8) y maná 8/s y 18/s sin gastar (14 y 30).
- Armas: sin cambios por ahora (el rediseño del "pistolero" va en el bloque 4).

## 8. Correcciones de las pruebas con amigos, bloque 2: interfaz

- Mejoras de oleada: las 3 cartas salen boca abajo y se dan la vuelta una a una
  (`WaveController`, ~1,3 s); hasta entonces no se pueden elegir (antes se cogía la
  primera sin leer). Para elegir hay 10 s (`WaveConfig.CardSeconds`, antes 8).
- Armería: cada arma lleva el icono de su categoría (🔫 Armas, 🗡️ Guerrero, 🥊 Puños,
  🔱 Magia; `WeaponConfig.Categories[].ItemIcon`) y su elemento en una insignia pequeña:
  las espadas ya no parecen orbes.
- Avisos: más pequeños (360 px de ancho, antes 420), como mucho 3 a la vez (4) y duran
  menos (2,2 s; con título 4,5 s) (`HudLayout.Sizes`, `Toasts`).
- ⚙️ Ajustes (`SettingsController`): tamaño de la interfaz del 60 % al 100 %
  (`SettingsLogic.HudScales`). Multiplica la escala de `HudLayout` (puede bajar de su
  mínimo) y se aplica al momento a todo el HUD y a los paneles (`UserScale`); se guarda
  con la partida (`SetSetting` → `SettingsService`, campo `Settings` del guardado, opcional:
  sin él, 100 %). Botón de engranaje abajo a la izquierda (escritorio) o arriba en la
  columna izquierda (táctil). Más grande que el 100 % no cabe en pantallas pequeñas (lo
  comprueba la suite "hudlayout" con cada tamaño).

## 9. Correcciones de las pruebas con amigos, bloque 3: enemigos y jefes

- Bichos a distancia (`Def.Ranged`, `EnemyService.Ai`): se paran a tiro, avisan el disparo
  (ojos y ¡! sobre su objetivo, sin media luna: `AttackKind = "Shot"`) y la bola va a donde
  estabas al soltarla (moverse la esquiva). Si te acercas mientras recargan, retroceden; pegados
  a ti golpean como los demás. Uno nuevo por zona con su propio modelo (`Rigs` estilo "Caster":
  brujo con túnica y bastón): Brujo Espinoso (Bosque), Hechicero de Cristal (Valle), Piromante
  (Caldera) y Chamán de Escarcha (Tundra). En las oleadas sustituyen a 1 de cada 4 bichos
  normales desde la 3.ª (y 2 en la escolta del jefe); dan el mismo botín que el bicho al que
  sustituyen, así que el ritmo de 💰 y 💎 no cambia. Hay unos pocos también por el mundo. En
  las Tierras Divididas, los Espíritus de Escarcha disparan hielo.
- Jefes:
  - Persecución (`EnemyConfig.Pursuit`, `EnemyLogic.pursuitBoost`): si te alejas de su alcance
    más de 1,5 s, aceleran poco a poco (hasta ×2,2) sin pasar del 95 % de tu velocidad. Ya no
    se les puede dar vueltas sin peligro.
  - Peligros de su arena (`Def.Hazard`, `BossAttacks`): cada ~7 s caen avisos en el suelo
    donde está cada jugador (y por la arena): espinas que ralentizan (Guardián), cristales que
    caen (Coloso de Amatista), erupciones de lava (Titán, Ignis, el Coloso del Equilibrio),
    carámbanos que congelan (Gólem de Hielo, Glacius) y rocas (Rey Goblin). Con furia, más
    seguidos.
- Atascos: si un bicho que te persigue casi no se mueve, salta; si sigue, rodea por un lado; y
  tras 6 s vuelve a su sitio (`Ai.handleStuck`).
- Modo infinito: cada 5 oleadas tras el jefe vuelve el jefe del modo con su escolta y +40 % de
  vida cada vez (`WaveConfig.Endless.BossEvery` y `BossHealthGrowth`, `WaveLogic.isEndlessBossWave`).
  Al derrotarlo es una oleada superada más.

## 10. Correcciones de las pruebas con amigos, bloque 4 (1): dash, defensa y pociones

- Dash para todos (`StyleConfig.Dash`: 14 studs cada 3,5 s; `StyleLogic.dashSpec`): Shift, el
  stick izquierdo pulsado o el botón 💨 (también con teclado, con la tecla debajo). Puños tiene
  el suyo (16 studs cada 2,5 s) y Magia su teletransporte.
- Raíces ya no es la Q de Naturaleza (`AbilityConfig.Abilities.Nature.Skill = false`,
  `AbilityLogic.castable`): sin otro núcleo no hay botón Q. Con Naturaleza de principal y otro
  de secundario, el secundario pasa a la Q. Sus datos siguen para las marcas y los combos.
- Mejoras defensivas con 💰 en ⚡ Mejoras (junto a la Velocidad): Vitalidad (+6 % de vida por
  nivel, hasta 10) y Armadura (-3 % de daño recibido por nivel, hasta 10).
- Poción de Vida (❤️): cura al momento la mitad de la vida máxima (no con la vida llena; 6 s
  entre dos). Tecla Y (↑ en el mando) o el botón junto al ⚙️ (late en rojo con poca vida).
  La sueltan el 3 % de los normales, el 12 % de los fuertes y todos los jefes (`HealthDrops`).
  No sale en los cofres ni en el sorteo de impulsos (`ItemLogic.boostOrder`).

## 11. Bloque 4 (2): el pistolero pasa a Arquero

Las armas de fuego no pegaban con el tema medieval. El estilo "Weapons" se llama ahora
🏹 **Arquero**, con los mismos números (daño, cadencia, carcaj, alcance, críticos y clases):
- Tipos (`WeaponConfig.Guns`, mismos ids): Pistol → ballesta de mano, Rifle → ballesta de
  repetición, Shotgun → ballesta de abanico, Sniper → arbalesta, Launcher → balista de mano.
  Modelos nuevos en `GearModels` (tablero, arco, cuerdas y virote con la punta del color del
  arma); el Arco de espinas sigue siendo un arco.
- Armas: Ballesta de aprendiz, Ballesta de pólvora, Ballesta de cristal, Arbalesta de amatista,
  Balista del vacío… (los ids no cambian: las partidas guardadas siguen igual). Sin las
  ilustraciones de pistolas: la tarjeta enseña 🏹 y el elemento.
- Disparos: flechas que vuelan con estela y se clavan (`CombatController.arrowFx`), sin
  fogonazo; la balista lanza un virote con bomba. Sonidos de cuerda en vez de tiros.
- Habilidades: Tiro rápido, Bomba de brea, Flecha perforante, Balista; Mundo 2: Lluvia de
  bombas, Triple flecha, Furia del arquero y Balista de asedio. Clases: Guardabosques, Tirador
  certero, Ballestero, Artificiero y Maestro arquero.

## 12. Bloque 4 (3): clases de mascota

Cada mascota tiene una clase según su forma (`PetConfig.StyleClasses`; las clásicas, `ClassById`)
y, además de su multiplicador de siempre, da su bonificación: `Base` × `ClassPower` de su rareza
(Común 1 … Mítica 5), sumando las equipadas y con tope (`PetClassLogic`):
- ⚔️ Atacante (dragones, zorritos de brasa y de cuarzo, perrito): +3 % de daño (tope +60 %).
- 🛡️ Tanque (tortugas, osito): -3 % de daño recibido (tope -35 %).
- 💚 Sanadora (setas, búhos, cervatillos): cura 0,15 % de la vida por segundo, también
  peleando (tope 1,5 %/s).
- 💰 Recolectora (brotes, zorros, conejito): +5 % de 💰 (tope +100 %).
Se ve en cada tarjeta de mascota (rareza · clase · lo que da), al abrir un huevo y en el resumen
de las equipadas. Lo aplican `PlayerDataService` (daño), `StyleService` (daño recibido),
`HealthService` (cura) y `EnemyService` (💰).

## 13. Bloque 4 (4): tutorial más claro y obligatorio al principio

- Textos cortos y en pasos numerados, con la tecla de cada cosa y "sigue la flecha"
  (`TutorialConfig.Steps`); enseña también el dash (Shift), las clases de mascota y la ❤️
  poción (Y).
- No se puede omitir hasta hacer los 2 primeros pasos (primera oleada y mejorar el arma:
  `TutorialConfig.MinSkipStep`, `TutorialLogic.canSkip`); antes, el botón Omitir no sale y el
  servidor lo ignora.

## 14. Bloque 4 (5): personajes con clase fija

Cambiar de clase a mitad de partida no tenía gracia. Ahora cada cuenta tiene hasta 3
**personajes** (⚙️ Ajustes → 👤 Personajes), cada uno con su clase fija y su propio progreso:
💰, 💎, armas, mascotas, zonas, renacimientos, misiones… Lo comprado con Robux en **pases** es
de la cuenta (vale para todos); las compras sueltas (💎, pociones) van al personaje con el que
juegas.
- Cuenta (`ProfileLogic`, DataStore `RebirthCity_Accounts_v1`, entrada `account_<id>`): los
  huecos (clase, renacimientos y mejor zona, para la lista) y con cuál se entra (`Last`). Se lee
  al entrar (`SaveService.loadAccount`); si no se puede, se juega con el 1 y no se puede cambiar
  ni se guarda la cuenta. Al guardarla se juntan los huecos guardados (`ProfileLogic.merge`):
  un guardado viejo nunca borra un personaje.
- Cada personaje guarda su partida en su entrada (`SaveService.keyFor`): el 1 es la de siempre
  (`player_<id>`; las partidas de antes siguen ahí) y los demás `player_<id>_s<hueco>`.
- El personaje de antes de los personajes no tiene clase fija (`FixedStyle` = nil) y cambia de
  estilo como siempre. Uno nuevo entra ya con su clase (no se le pregunta) y un jugador nuevo
  fija la clase que elige al empezar (solo si su partida se guarda y hay personajes: en Studio
  sin acceso a la API no se fija y cambia de estilo como siempre). Con clase fija, ⇄ y la tecla C no salen y el servidor
  rechaza el cambio (`StyleService`, código `Locked`).
- Crear o elegir (`ProfileService`, remotos `ProfileAction` / `ProfileResult`): guarda la cuenta
  y la partida y te hace volver a entrar al juego (`TeleportService`; si no se puede, p. ej. en
  Studio, te saca con un mensaje para que vuelvas a entrar). Si la cuenta no se puede guardar,
  no se cambia nada.
- Atributos para el cliente: `Profiles` (la lista: `hueco:clase:renacimientos:zona|…`),
  `ProfileSlot` y `FixedStyle`. Pruebas: batería `profiles`.

## 15. Bloque 4 (6): equipo visible

No se notaba la clase ni lo que mejorabas. Además de lo que llevas en la mano, `GearService`
viste al personaje (`OutfitLogic`, modelos en `GearModels.outfit`, R15 y R6; nada choca ni se
puede apuntar):
- Pieza de cada clase, del color de la clase: 🏹 carcaj con flechas a la espalda y correa al
  pecho, ⚔️ escudo redondo a la espalda, 👊 cinta en la frente con colas y fajín, ✨ capa con
  hombros y broches dorados.
- Armadura según su nivel (`OutfitLogic.ArmorTiers`): desde el 1 hombreras de cuero, desde el 4
  de hierro (dos placas), desde el 7 de acero con peto y al 10 todo dorado con un brillo del
  color de la clase.
- Se rehace al cambiar de estilo, al subir de grado (atributo `UpgradeLevel_Armor`) y al
  reaparecer. Pruebas en la batería `styles`.
