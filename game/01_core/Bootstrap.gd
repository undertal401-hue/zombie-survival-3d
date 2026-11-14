extends Node
## Bootstrap: precarga todas las clases class_name para registrar sus tipos
## antes de que se instancien los autoloads principales.
##
## Debe ser el PRIMER autoload en project.godot.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Precarga forzada de todas las class_name para registro temprano
	# 01_core
	preload("res://01_core/Config.gd")
	preload("res://01_core/GameClock.gd")
	preload("res://01_core/ObjectPool.gd")
	preload("res://01_core/EventBus.gd")
	preload("res://01_core/GameManager.gd")
	# 02_player
	preload("res://02_player/Player.gd")
	preload("res://02_player/PlayerStats.gd")
	preload("res://02_player/Inventory.gd")
	preload("res://02_player/InputHandler.gd")
	preload("res://02_player/PlayerController.gd")
	preload("res://02_player/PlayerCamera.gd")
	preload("res://02_player/InteractionComponent.gd")
	preload("res://02_player/PlayerAudio.gd")
	# 03_zombies - base primero
	preload("res://03_zombies/ZombieStats.gd")
	preload("res://03_zombies/BaseZombie.gd")
	preload("res://03_zombies/ZombieAI.gd")
	preload("res://03_zombies/ZombieTypes.gd")
	preload("res://03_zombies/ZombiePool.gd")
	preload("res://03_zombies/ZombieSpawner.gd")
	preload("res://03_zombies/ZombieLoot.gd")
	preload("res://03_zombies/ZombieSenses.gd")
	# derivados
	preload("res://03_zombies/WalkerZombie.gd")
	preload("res://03_zombies/RunnerZombie.gd")
	preload("res://03_zombies/TankZombie.gd")
	preload("res://03_zombies/SpitterZombie.gd")
	preload("res://03_zombies/CrawlerZombie.gd")
	preload("res://03_zombies/ScreamerZombie.gd")
	preload("res://03_zombies/BruteZombie.gd")
	preload("res://03_zombies/MutatedZombie.gd")
	# 04_weapons - base primero
	preload("res://04_weapons/WeaponData.gd")
	preload("res://04_weapons/BaseWeapon.gd")
	preload("res://04_weapons/RangedWeapon.gd")
	preload("res://04_weapons/MeleeWeapon.gd")
	preload("res://04_weapons/WeaponManager.gd")
	preload("res://04_weapons/ReloadSystem.gd")
	preload("res://04_weapons/RecoilComponent.gd")
	preload("res://04_weapons/ADSComponent.gd")
	preload("res://04_weapons/Projectile.gd")
	preload("res://04_weapons/ProjectilePool.gd")
	preload("res://04_weapons/BulletTracer.gd")
	# 05_combat
	preload("res://05_combat/DamageInfo.gd")
	preload("res://05_combat/DamageSystem.gd")
	preload("res://05_combat/HitboxComponent.gd")
	preload("res://05_combat/HurtboxComponent.gd")
	preload("res://05_combat/BloodSystem.gd")
	preload("res://05_combat/KnockbackSystem.gd")
	preload("res://05_combat/ImpactSystem.gd")
	preload("res://05_combat/CriticalHit.gd")
	preload("res://05_combat/ExplosionSystem.gd")
	# 06_waves
	preload("res://06_waves/WaveManager.gd")
	preload("res://06_waves/WaveTimer.gd")
	preload("res://06_waves/WaveData.gd")
	preload("res://06_waves/WaveScaling.gd")
	preload("res://06_waves/WaveComposition.gd")
	preload("res://06_waves/WeightedPicker.gd")
	preload("res://06_waves/ShopPhase.gd")
	preload("res://06_waves/WaveReward.gd")
	# 07_house - base primero
	preload("res://07_house/RoomLayout.gd")
	preload("res://07_house/Room.gd")
	preload("res://07_house/Corridor.gd")
	preload("res://07_house/SafeZone.gd")
	preload("res://07_house/Bathroom.gd")
	preload("res://07_house/HouseGenerator.gd")
	# 08_ui
	preload("res://08_ui/HUD.gd")
	preload("res://08_ui/HealthBar.gd")
	preload("res://08_ui/StaminaBar.gd")
	preload("res://08_ui/InfectionBar.gd")
	preload("res://08_ui/ShopUI.gd")
	preload("res://08_ui/PauseMenu.gd")
	preload("res://08_ui/Notifications.gd")
	# 09_audio
	preload("res://09_audio/AudioManager.gd")
	preload("res://09_audio/SFXPlayer.gd")
	preload("res://09_audio/MusicManager.gd")
	# 11_items
	preload("res://11_items/ItemBase.gd")
	preload("res://11_items/AmmoPickup.gd")
	preload("res://11_items/Food.gd")
	preload("res://11_items/Potion.gd")
	preload("res://11_items/HealthKit.gd")
	preload("res://11_items/Consumable.gd")
	preload("res://11_items/PermanentUpgrade.gd")
	preload("res://11_items/PermanentUpgradePickup.gd")
	preload("res://11_items/CoinPickup.gd")
	preload("res://11_items/ItemFactory.gd")
	# 12_economy
	preload("res://12_economy/Currency.gd")
	preload("res://12_economy/Shop.gd")
	preload("res://12_economy/PriceTable.gd")
	preload("res://12_economy/Rarity.gd")
	preload("res://12_economy/LootTable.gd")
	preload("res://12_economy/DropCalculator.gd")
	preload("res://12_economy/EconomyConfig.gd")
	preload("res://12_economy/Transaction.gd")
	# 13_save
	preload("res://13_save/SaveSystem.gd")
	preload("res://13_save/Checkpoint.gd")
	preload("res://13_save/Progress.gd")
	# 14_debug
	preload("res://14_debug/DebugConsole.gd")
	preload("res://14_debug/Profiler.gd")
	preload("res://14_debug/Cheats.gd")
	preload("res://14_debug/Gizmos.gd")
	preload("res://14_debug/SceneValidator.gd")

	print("Bootstrap: todas las class_name registradas")