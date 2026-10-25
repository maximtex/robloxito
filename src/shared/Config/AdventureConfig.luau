-- Aventuras opcionales: cinco personajes (NPCs) con una historia de tres misiones cada
-- uno (Brasa, la herrera, vive en la Caldera de Brasas, la zona de los renacimientos).
-- Nada es obligatorio: el jugador habla con ellos si quiere.
-- - Cada misión se acepta hablando con su personaje y se entrega volviendo a él.
-- - Tipos de objetivo (Goal):
--     { Type = "Kill", Enemies = { TypeId... }, Target }  derrotar enemigos (cuentan desde
--         que se acepta; un jefe cuenta para quien recibe parte de su recompensa).
--     { Type = "Collect", Items = { ItemId... } }  encontrar objetos perdidos por el mapa
--         (solo los ve quien tiene la misión; se recogen al pasar cerca).
--     { Type = "Talk", Npc = NpcId }  llevar algo a otro personaje (hablar con él).
-- - Recompensas (Reward): 💰 (la calcula el servidor al entregar:
--   clamp(Share · coste de la siguiente mejora de Resonancia, Min, Max)), una bendición para usar cuando se quiera y, al final de cada historia, un
--   amuleto con una pasiva.
-- - Amuletos: se lleva uno a la vez (ranura 1); al terminar las cuatro historias del
--   Bosque y del Valle (SlotStories) se abre la segunda ranura.
-- - Bendiciones: se guardan y se activan cuando el jugador quiere; duran Duration
--   segundos de tiempo real (activar otra igual alarga la que está activa, hasta
--   MaxActiveSeconds).
-- Posiciones RELATIVAS al centro de cada zona, en X/Z, igual que LandscapeConfig y
-- EnemyConfig (Bosque: el cristal; Valle: su centro). LandscapeLayout deja libres los
-- sitios de los personajes y de los objetos, y EnemyService no deja que los enemigos
-- persigan a nadie junto a un personaje.

local V2 = Vector2.new

local AdventureConfig = {
	InteractDistance = 14, -- para hablar, aceptar o entregar (lo comprueba el servidor)
	CollectRadius = 5, -- distancia horizontal para recoger un objeto perdido
	CollectHeight = 12, -- diferencia de altura máxima al recogerlo
	NpcSafeRadius = 11, -- los enemigos no persiguen a nadie tan cerca de un personaje
	RewardUpgradeId = "GeneratorPower",
	MaxActiveSeconds = 3600, -- tope de una bendición alargada
	ActionRateLimit = { Cooldown = 0.3, WindowSeconds = 3, MaxPerWindow = 8 },
	RequestRateLimit = { Cooldown = 1, WindowSeconds = 5, MaxPerWindow = 6 },
	PushInterval = 1, -- como mucho un envío de estado por segundo (salvo tras una acción)

	Npcs = {
		Herbalist = {
			Order = 1,
			DisplayName = "Abuela Hiedra",
			Title = "Herbolaria",
			Zone = "Forest",
			Where = "Pradera del este, junto al sendero",
			Position = V2(50, 40), -- al norte del Jardín de los Huevos, junto al camino este
			Facing = V2(36, 40), -- mira hacia la plaza del pueblo
			Look = {
				Style = "Herbalist",
				Skin = Color3.fromRGB(240, 200, 170),
				Primary = Color3.fromRGB(96, 150, 84), -- capa verde
				Secondary = Color3.fromRGB(226, 196, 132), -- sombrero de paja
				Accent = Color3.fromRGB(255, 160, 196), -- flores
				Hair = Color3.fromRGB(236, 236, 240),
			},
			Greeting = "Gracias a ti mi huerto vuelve a oler a menta. ¡Pásate cuando quieras, cielo!",
			Amulet = "Sap",
			Steps = {
				{
					Title = "Flores de rocío",
					Objective = "Encuentra las flores de rocío en la pradera",
					Offer = "¡Ay, qué bien que pasas! El viento me desparramó las flores de rocío por la pradera del este. ¿Me ayudas a juntar las 5? Brillan, no tienen pérdida.",
					Active = "Las flores brillan con una luz celeste. Busca por la pradera del este, más allá del Jardín de los Huevos.",
					Ready = "¡Mis flores! Con esto preparo mis tés. Toma, una bendición de mi huerto.",
					Goal = { Type = "Collect", Items = { "Dew1", "Dew2", "Dew3", "Dew4", "Dew5" } },
					Reward = { Money = { Min = 500, Share = 1, Max = 10000 }, Blessing = "Abundance" },
				},
				{
					Title = "Fuera, Espinillos",
					Objective = "Derrota Espinillos",
					Offer = "Los Espinillos me pisotean los brotes cada noche. ¿Les das un susto? Con 8 creo que entienden.",
					Active = "Todavía oigo crujir ramitas... ¡quedan Espinillos por la pradera!",
					Ready = "Mira qué tranquilo quedó todo. Ten, te lo ganaste.",
					Goal = { Type = "Kill", Enemies = { "Thornling" }, Target = 8 },
					Reward = { Money = { Min = 1000, Share = 1.5, Max = 20000 }, Blessing = "Abundance" },
				},
				{
					Title = "Un remedio para Tavo",
					Objective = "Lleva el ungüento a Tavo el Cazador",
					Offer = "Tavo, el cazador del camino del oeste, se torció el tobillo. ¿Le llevas este ungüento? Yo ya no camino tan lejos.",
					Active = "Tavo está junto al camino del oeste, pasando el cartel del Guardián.",
					Delivery = "¿Un ungüento de la abuela Hiedra? ¡Bendita sea! Ya me siento mejor. Dile que muchas gracias.",
					Ready = "¿Ya se lo llevaste? Eres un sol. Toma mi Amuleto de Savia: me acompañó cuarenta años, ahora te toca a ti.",
					Goal = { Type = "Talk", Npc = "Hunter" },
					Reward = { Money = { Min = 2000, Share = 2, Max = 40000 }, Amulet = "Sap" },
				},
			},
		},
		Hunter = {
			Order = 2,
			DisplayName = "Tavo",
			Title = "Cazador",
			Zone = "Forest",
			Where = "Camino del oeste, cerca del cartel del Guardián",
			Position = V2(-54, 15),
			Facing = V2(-44, 18),
			Look = {
				Style = "Hunter",
				Skin = Color3.fromRGB(214, 160, 120),
				Primary = Color3.fromRGB(70, 110, 64), -- capucha verde bosque
				Secondary = Color3.fromRGB(128, 86, 54), -- cuero
				Accent = Color3.fromRGB(214, 70, 60), -- plumas rojas
				Hair = Color3.fromRGB(70, 46, 30),
			},
			Greeting = "El bosque está más tranquilo desde que andas por aquí. ¡Buena caza!",
			Amulet = "Fang",
			Steps = {
				{
					Title = "Corteza dura",
					Objective = "Derrota Brutos de Corteza",
					Offer = "Los Brutos de Corteza no dejan pasar a nadie. Derriba a 3 y te enseño un par de trucos.",
					Active = "Los Brutos rondan los extremos del bosque, al oeste y al este. Pegan fuerte: esquiva cuando levanten los brazos.",
					Ready = "¡Ja! Sabía que tenías buen brazo. Toma esto para tu próxima pelea.",
					Goal = { Type = "Kill", Enemies = { "Barkbrute" }, Target = 3 },
					Reward = { Money = { Min = 750, Share = 1.2, Max = 15000 }, Blessing = "Fury" },
				},
				{
					Title = "Flechas perdidas",
					Objective = "Encuentra las flechas perdidas",
					Offer = "Persiguiendo a un Bruto se me rompió la aljaba y dejé flechas por todo el oeste. ¿Me traes las 4?",
					Active = "Mis flechas tienen plumas rojas y brillan entre el pasto, por el camino del oeste.",
					Ready = "¡Mis flechas! Con estas vuelvo a cazar. Ten tu recompensa.",
					Goal = { Type = "Collect", Items = { "Arrow1", "Arrow2", "Arrow3", "Arrow4" } },
					Reward = { Money = { Min = 1000, Share = 1.5, Max = 20000 }, Blessing = "Fury" },
				},
				{
					Title = "El Guardián del Bosque",
					Objective = "Derrota al Guardián del Bosque",
					Offer = "Ahora, la prueba de verdad: el Guardián del Bosque, en su círculo de piedras al noroeste. Derrótalo y serás cazador de honor.",
					Active = "El Círculo del Guardián está al final del camino del oeste. Cuando golpee el suelo, ¡aléjate!",
					Ready = "¡Lo lograste! Este Colmillo del Cazador es tuyo: con él vas a pegar más fuerte.",
					Goal = { Type = "Kill", Enemies = { "ForestWarden" }, Target = 1 },
					Reward = { Money = { Min = 2500, Share = 2.5, Max = 45000 }, Amulet = "Fang" },
				},
			},
		},
		Explorer = {
			Order = 3,
			DisplayName = "Pip",
			Title = "Explorador",
			Zone = "Forest",
			Where = "Junto al estanque del norte",
			Position = V2(12, 100), -- entre la plaza del pueblo y el estanque
			Facing = V2(6, 92),
			Look = {
				Style = "Explorer",
				Skin = Color3.fromRGB(250, 214, 180),
				Primary = Color3.fromRGB(232, 150, 70), -- chaqueta naranja
				Secondary = Color3.fromRGB(226, 208, 160), -- casco de explorador
				Accent = Color3.fromRGB(214, 64, 64), -- pañuelo
				Hair = Color3.fromRGB(160, 92, 40),
			},
			Greeting = "¡El mapa del bosque está completo gracias a ti! ¿Cuál será nuestra próxima aventura?",
			Amulet = "Feather",
			Steps = {
				{
					Title = "El mapa roto",
					Objective = "Encuentra los trozos del mapa por el bosque",
					Offer = "¡Hola! Soy Pip. Un ventarrón se llevó mi mapa del bosque y se rompió en 5 trozos. ¡Hay uno hasta en la torre del vigía! ¿Me ayudas a encontrarlos?",
					Active = "Los trozos brillan en dorado: uno cerca de la torre del vigía, otro junto a las setas gigantes, otro detrás del árbol ancestral... ¡explora!",
					Ready = "¡El mapa entero! Bueno, con un poco de cinta. ¡Toma, te lo mereces!",
					Goal = { Type = "Collect", Items = { "Map1", "Map2", "Map3", "Map4", "Map5" } },
					Reward = { Money = { Min = 1000, Share = 1.5, Max = 20000 }, Blessing = "Fortune" },
				},
				{
					Title = "Carta para el Valle",
					Objective = "Lleva el mapa a Lumi, en el Valle Cristalino",
					Offer = "Quiero enseñarle el mapa a Lumi, la oráculo del Valle Cristalino. Yo todavía no puedo cruzar el portal... ¿se lo llevas tú?",
					Active = "Lumi vive en el Valle Cristalino, al lado del camino de llegada. El portal está al norte del spawn.",
					Delivery = "¿Un mapa del bosque, de parte de Pip? ¡Qué detallado! Dile que lo guardaré junto a mis cristales.",
					Ready = "¿¡Lumi lo vio!? ¡Increíble! Toma, ¡gracias, gracias!",
					Goal = { Type = "Talk", Npc = "Oracle" },
					Reward = { Money = { Min = 3000, Share = 1.5, Max = 30000 }, Blessing = "Fortune" },
				},
				{
					Title = "Fragmentos inquietos",
					Objective = "Derrota Fragmentos Errantes en el Valle",
					Offer = "Lumi me escribió: hay Fragmentos Errantes molestando en el valle. Derrota 10 y te regalo mi tesoro más preciado.",
					Active = "Los Fragmentos Errantes andan por el oeste y el norte del Valle Cristalino.",
					Ready = "¡Eres el mejor explorador que conozco! Ten mi Pluma del Viento: con ella vas a correr como el viento.",
					Goal = { Type = "Kill", Enemies = { "Shardling" }, Target = 10 },
					Reward = { Money = { Min = 6000, Share = 2, Max = 50000 }, Amulet = "Feather" },
				},
			},
		},
		Oracle = {
			Order = 4,
			DisplayName = "Lumi",
			Title = "Oráculo del Cristal",
			Zone = "CrystalValley",
			Where = "Valle Cristalino, junto al camino de llegada",
			Position = V2(13, 37),
			Facing = V2(3, 34),
			Look = {
				Style = "Oracle",
				Skin = Color3.fromRGB(250, 220, 200),
				Primary = Color3.fromRGB(122, 92, 196), -- túnica violeta
				Secondary = Color3.fromRGB(70, 56, 140), -- capucha
				Accent = Color3.fromRGB(90, 190, 255), -- cristal
				Hair = Color3.fromRGB(196, 170, 240), -- melena lavanda
			},
			Greeting = "Los cristales cantan tu nombre, viajero. Que su luz te acompañe.",
			Amulet = "Geode",
			Steps = {
				{
					Title = "Gólems inquietos",
					Objective = "Derrota Gólems de Geoda",
					Offer = "Bienvenido al Valle Cristalino, viajero. Los Gólems de Geoda están inquietos... Derrota a 3 y los cristales recuperarán la calma.",
					Active = "Los Gólems son lentos pero duros. Buscan sombra al oeste y al sur del valle.",
					Ready = "Siento la calma volver. Acepta esta bendición.",
					Goal = { Type = "Kill", Enemies = { "GeodeGolem" }, Target = 3 },
					Reward = { Money = { Min = 4000, Share = 1.5, Max = 30000 }, Blessing = "Fortune" },
				},
				{
					Title = "Esquirlas de luz",
					Objective = "Encuentra las esquirlas de luz por el valle",
					Offer = "Cinco esquirlas de luz cayeron del cielo esta noche. Si las juntas, podré leer el futuro. Están repartidas por todo el valle.",
					Active = "Las esquirlas brillan en violeta: mira cerca de la gran geoda, junto al lago y hacia las montañas.",
					Ready = "Con ellas veo... a alguien muy fuerte. Sí: eres tú. Toma.",
					Goal = { Type = "Collect", Items = { "Shard1", "Shard2", "Shard3", "Shard4", "Shard5" } },
					Reward = { Money = { Min = 6000, Share = 2, Max = 45000 }, Blessing = "Abundance" },
				},
				{
					Title = "El Coloso de Amatista",
					Objective = "Derrota al Coloso de Amatista",
					Offer = "El Coloso de Amatista despierta en su trono, al este del valle. Detenlo y te daré el corazón de la geoda.",
					Active = "El Trono de Amatista está al este del valle, siguiendo el camino de faroles.",
					Ready = "Lo has logrado. Este Corazón de Geoda ahora late por ti: los enemigos te darán más botín.",
					Goal = { Type = "Kill", Enemies = { "AmethystColossus" }, Target = 1 },
					Reward = { Money = { Min = 12500, Share = 3, Max = 75000 }, Amulet = "Geode" },
				},
			},
		},
		Smith = {
			Order = 5,
			DisplayName = "Brasa",
			Title = "Herrera de la Caldera",
			Zone = "EmberCaldera",
			Where = "Caldera de Brasas, junto al camino de llegada",
			Position = V2(-14, 34),
			Facing = V2(-4, 36),
			Look = {
				Style = "Smith",
				Skin = Color3.fromRGB(214, 160, 120),
				Primary = Color3.fromRGB(156, 74, 52), -- camisa rojiza
				Secondary = Color3.fromRGB(98, 68, 48), -- delantal de cuero
				Accent = Color3.fromRGB(255, 140, 50), -- brasa
				Hair = Color3.fromRGB(232, 112, 52), -- melena pelirroja
			},
			Greeting = "¡Bienvenido a la caldera! Aquí el calor forja a los valientes.",
			Amulet = "Magma",
			Steps = {
				{
					Title = "Chispas descontroladas",
					Objective = "Derrota Chispas Ígneas",
					Offer = "Las Chispas Ígneas se escaparon de mi fragua y queman todo a su paso. Apaga a 10 y te daré algo que vale la pena.",
					Active = "Las Chispas saltan por toda la caldera, sobre todo al oeste y al este del camino.",
					Ready = "¡Ya no chisporrotean! Toma esta bendición, te la has ganado.",
					Goal = { Type = "Kill", Enemies = { "Cinderling" }, Target = 10 },
					Reward = { Money = { Min = 15000, Share = 1.5, Max = 100000 }, Blessing = "Fury" },
				},
				{
					Title = "Núcleos de brasa",
					Objective = "Encuentra los núcleos de brasa por la caldera",
					Offer = "Para forjar algo digno de ti necesito cinco núcleos de brasa. Los escupió el volcán en su última erupción y quedaron repartidos por la caldera.",
					Active = "Los núcleos brillan en naranja: busca cerca del lago de lava, junto a la obsidiana y hacia las montañas.",
					Ready = "¡Qué calorcito más bueno! La fragua ya ruge. Toma.",
					Goal = { Type = "Collect", Items = { "Ember1", "Ember2", "Ember3", "Ember4", "Ember5" } },
					Reward = { Money = { Min = 22500, Share = 2, Max = 150000 }, Blessing = "Abundance" },
				},
				{
					Title = "El Titán de la Caldera",
					Objective = "Derrota al Titán de la Caldera",
					Offer = "El Titán de la Caldera despertó junto al volcán. Si lo derrotas, forjaré para ti el Corazón de Magma.",
					Active = "El Corazón de la Caldera está al fondo, siguiendo el camino hacia el volcán.",
					Ready = "¡Lo hiciste! Aquí tienes el Corazón de Magma: tu cristal arderá como nunca.",
					Goal = { Type = "Kill", Enemies = { "CalderaTitan" }, Target = 1 },
					Reward = { Money = { Min = 45000, Share = 3, Max = 250000 }, Amulet = "Magma" },
				},
			},
		},
	},

	-- Objetos perdidos (misiones Collect). Kind decide su aspecto (ItemKinds).
	Items = {
		Dew1 = { Kind = "Dew", Zone = "Forest", Position = V2(64, 100) }, -- (fuera del Jardín de los Huevos)
		Dew2 = { Kind = "Dew", Zone = "Forest", Position = V2(67.3, 26.2) },
		Dew3 = { Kind = "Dew", Zone = "Forest", Position = V2(70.2, 57.9) },
		Dew4 = { Kind = "Dew", Zone = "Forest", Position = V2(24, 118) }, -- (fuera del Jardín de los Huevos)
		Dew5 = { Kind = "Dew", Zone = "Forest", Position = V2(78, 39) },
		Arrow1 = { Kind = "Arrow", Zone = "Forest", Position = V2(-62.8, 3.9) },
		Arrow2 = { Kind = "Arrow", Zone = "Forest", Position = V2(-69.8, 31.2) },
		Arrow3 = { Kind = "Arrow", Zone = "Forest", Position = V2(-34, 64) },
		Arrow4 = { Kind = "Arrow", Zone = "Forest", Position = V2(-78.4, -7.3) },
		Map1 = { Kind = "Map", Zone = "Forest", Position = V2(-58, 96) }, -- torre del vigía
		Map2 = { Kind = "Map", Zone = "Forest", Position = V2(-63.4, -63.8) }, -- setas gigantes
		Map3 = { Kind = "Map", Zone = "Forest", Position = V2(18, -76) }, -- detrás del árbol ancestral
		Map4 = { Kind = "Map", Zone = "Forest", Position = V2(98, 84) }, -- pico de cristal
		Map5 = { Kind = "Map", Zone = "Forest", Position = V2(52, 118) }, -- tras el estanque
		Shard1 = { Kind = "Shard", Zone = "CrystalValley", Position = V2(-46, -6) },
		Shard2 = { Kind = "Shard", Zone = "CrystalValley", Position = V2(-26, -72) }, -- junto a la geoda
		Shard3 = { Kind = "Shard", Zone = "CrystalValley", Position = V2(66, 48) }, -- cerca del lago
		Shard4 = { Kind = "Shard", Zone = "CrystalValley", Position = V2(66, -44) },
		Shard5 = { Kind = "Shard", Zone = "CrystalValley", Position = V2(-80, 56) },
		Ember1 = { Kind = "Ember", Zone = "EmberCaldera", Position = V2(-66, -24) }, -- tras el lago de lava
		Ember2 = { Kind = "Ember", Zone = "EmberCaldera", Position = V2(52, -14) },
		Ember3 = { Kind = "Ember", Zone = "EmberCaldera", Position = V2(74, 52) },
		Ember4 = { Kind = "Ember", Zone = "EmberCaldera", Position = V2(-28, -78) }, -- junto a la obsidiana
		Ember5 = { Kind = "Ember", Zone = "EmberCaldera", Position = V2(-88, 56) }, -- hacia las montañas
	},

	ItemKinds = {
		Dew = { DisplayName = "Flor de rocío", Plural = "flores de rocío", Icon = "🌼", Color = Color3.fromRGB(150, 220, 255), Glow = Color3.fromRGB(190, 240, 255) },
		Arrow = { DisplayName = "Flecha perdida", Plural = "flechas", Icon = "🏹", Color = Color3.fromRGB(214, 70, 60), Glow = Color3.fromRGB(255, 190, 150) },
		Map = { DisplayName = "Trozo del mapa", Plural = "trozos del mapa", Icon = "🗺", Color = Color3.fromRGB(236, 214, 160), Glow = Color3.fromRGB(255, 220, 120) },
		Shard = { DisplayName = "Esquirla de luz", Plural = "esquirlas", Icon = "✨", Color = Color3.fromRGB(196, 150, 255), Glow = Color3.fromRGB(220, 190, 255) },
		Ember = { DisplayName = "Núcleo de brasa", Plural = "núcleos de brasa", Icon = "🔥", Color = Color3.fromRGB(255, 118, 36), Glow = Color3.fromRGB(255, 200, 110) },
	},

	-- Amuletos: pasiva permanente mientras se lleva puesto. Effect.Stat:
	--   Production (poder del cristal: más 💎 y premios), Damage (ataques, habilidades
	--   y mascotas), Loot (botín, 💰 y 💎, al derrotar enemigos), WalkSpeed (velocidad al caminar).
	Amulets = {
		Sap = {
			Order = 1,
			DisplayName = "Amuleto de Savia",
			Icon = "🌿",
			Description = "+25 % de poder del cristal (más 💎 y premios)",
			Effect = { Stat = "Production", Value = 0.25 },
			Color = Color3.fromRGB(120, 220, 120),
		},
		Fang = {
			Order = 2,
			DisplayName = "Colmillo del Cazador",
			Icon = "🐺",
			Description = "+20 % de daño (ataques, habilidades y mascotas)",
			Effect = { Stat = "Damage", Value = 0.2 },
			Color = Color3.fromRGB(255, 120, 90),
		},
		Feather = {
			Order = 3,
			DisplayName = "Pluma del Viento",
			Icon = "💨",
			Description = "+20 % de velocidad al caminar",
			Effect = { Stat = "WalkSpeed", Value = 0.2 },
			Color = Color3.fromRGB(150, 230, 255),
		},
		Geode = {
			Order = 4,
			DisplayName = "Corazón de Geoda",
			Icon = "💎",
			Description = "+40 % de botín (💰 y 💎) al derrotar enemigos",
			Effect = { Stat = "Loot", Value = 0.4 },
			Color = Color3.fromRGB(200, 150, 255),
		},
		Magma = {
			Order = 5,
			DisplayName = "Corazón de Magma",
			Icon = "🌋",
			Description = "+50 % de poder del cristal (más 💎 y premios)",
			Effect = { Stat = "Production", Value = 0.5 },
			Color = Color3.fromRGB(255, 140, 60),
		},
	},
	-- Ranuras: una desde el principio; la segunda al terminar las historias de SlotStories
	-- (las cuatro del Bosque y del Valle: quien ya la tenía no la pierde con la Caldera).
	BaseSlots = 1,
	MaxSlots = 2,
	SlotStories = { "Herbalist", "Hunter", "Explorer", "Oracle" },

	-- Bendiciones: se activan cuando el jugador quiere.
	Blessings = {
		Abundance = {
			Order = 1,
			DisplayName = "Bendición de Abundancia",
			Icon = "🌾",
			Description = "×2 de poder del cristal (más 💎 y premios)",
			Effect = { Stat = "Production", Value = 1 },
			Duration = 600,
			Color = Color3.fromRGB(255, 214, 110),
		},
		Fury = {
			Order = 2,
			DisplayName = "Bendición de Furia",
			Icon = "🔥",
			Description = "+30 % de daño",
			Effect = { Stat = "Damage", Value = 0.3 },
			Duration = 600,
			Color = Color3.fromRGB(255, 120, 80),
		},
		Fortune = {
			Order = 3,
			DisplayName = "Bendición de Fortuna",
			Icon = "🍀",
			Description = "×2 de botín (💰 y 💎) al derrotar enemigos",
			Effect = { Stat = "Loot", Value = 1 },
			Duration = 600,
			Color = Color3.fromRGB(120, 230, 140),
		},
	},
	MaxBlessings = 99, -- de cada tipo, guardadas sin usar

	-- Presentación (cliente).
	Colors = {
		Offer = Color3.fromRGB(255, 214, 90), -- "!" dorado: tiene una misión para ti
		Ready = Color3.fromRGB(120, 240, 150), -- "?" verde: vuelve a entregarla
		Active = Color3.fromRGB(200, 204, 196), -- "…" gris: en curso
	},
	Sounds = {
		Talk = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.25, Pitch = 1.3 },
		Accept = { Id = "rbxassetid://9114518386", Volume = 0.6, Pitch = 1.2 },
		Collect = { Id = "rbxassetid://9116394876", Volume = 0.55, Pitch = 1.35 },
		Reward = { Id = "rbxassetid://9116394876", Volume = 0.7, Pitch = 1 },
		Blessing = { Id = "rbxassetid://9116394876", Volume = 0.6, Pitch = 0.8 },
	},
}

return AdventureConfig
