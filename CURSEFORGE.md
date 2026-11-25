# Tinkerwise

A toolbox for WoW Forever: independent modules you can turn on or off from a single window.

**Available in English and French**, based on your game language. All modules are on by default: type `/tw` to turn off the ones you don't want. Its window shows a page per section, a tab per module and a search box that finds any setting. Appearance, Default Settings and Minimap Button always stay on.

## Modules

**Preparation**
- **Check-up:** durability, food, water, potions, ammo, reagents, elixirs, bag space and unspent talent points; each check can be turned off. Thresholds for your class (soul shards, ammo for the weapon you wear, runes, pet food...), and a button at merchants that buys what is missing after showing the price
- **Potion Reminder:** shows the best potion in your bags that isn't on your action bars

**Character**
- **My Characters:** gold, level, rested XP, bags, bank and mail across your characters in one window, with search. Characters are sorted by game mode (PvE, PvP, Hardcore, RP, RP-PvP, detected automatically) and by groups you create, for instance to keep a guild's characters apart. Can be turned on for each character. Also lists professions, recipes, recipe cooldowns and reputations
- **Travel Journal:** the date of your new zones, levels, deaths and bosses, for each character (`/tw journal`)
- **Stat Changes:** gains and losses when your gear, buffs, form or talents change, plus a summary panel on level up
- **Class Bar:** your class utility spells on one more action bar (conjured food, portals, demons, stones, pet care, tracking...), with lists to choose from, the look and settings of the game's own bars and a box for each button and spell. It counts the soul shards of warlocks, and their soulstone button uses the stone in the bags or creates one

**Items**
- **Item Tooltips:** gains and losses compared with your gear, and Ctrl + C over an item, spell, quest or creature gives its Wowhead address to copy
- **Auto Vendor:** sells gray items and repairs your gear
- **Soul Shards:** for warlocks, destroys the soul shards above the number you choose to keep (off by default)

**Group**
- **Group Comfort:** accepts invitations from friends and guildmates, resurrections and, optionally, summons, and can turn down duels
- **Buffs and Thanks:** one button, outside combat, to buff yourself and your group, and to thank (and buff back) whoever buffs you, the thanks also going out by themselves if you like, to turn herb, mineral or treasure tracking back on and, for warlocks, to create a healthstone when they have none. Away from rest areas, it also reminds you of weapon stones, oils and poisons, of food that gives a buff and of your pet or demon
- **Trade Supplies:** for mages and warlocks, puts conjured water and food or a healthstone in the trade window, for the class and level of the other player. You always accept the trade yourself

**Chat**
- **Chat:** a new tab for each whisper conversation with a close button, group and guild tabs, class-colored names, timestamps, clickable links, a whisper alert, copying and resizable windows with a custom background

**Interface**
- **Dark Theme:** darkens unit frames, action bars, minimap, windows and tooltips with a tint of your choice or your class color, without moving anything; elite dragons stay gold
- **Appearance:** the Tinkerwise windows (configuration, check-up) in gold or in your class color
- **Unit Frames:** dresses the game's unit frames without rebuilding them: health in class or reaction colors, bar texture, class colored names, class icon instead of the portrait
- **Nameplates:** target and other plate sizes, class colors, health texture, arrows around your target and health percentage on the game's own nameplates
- **Minimap:** a square minimap with a bronze border (thickness and color of your choice), its icons in a column on the left or right with a drawer for the ones that don't fit, mouse wheel zoom and no zoom buttons
- **Interface Elements:** shows the micro menu, the bags bar and the quest tracker always, never or on mouseover (the quest tracker once folded), and hides the red error messages and their voice, always or in combat only

**Immersion**
- **Immersion Mode:** when the game's key hides the interface, adds black bars, keeps the elements you choose on screen and brings the interface back with a fade; it can also stage your quests as cinematic scenes
- **Death and Level Scenes:** black bands and a few words when you die or gain a level
- **AFK and Flight Modes:** each can be turned on separately. When you're away, fades out the interface and slowly turns the camera around your character, showing your time away and the whispers you received. During a flight master trip, fades out the interface and shows your destination, the zone below and the flight time, with a progress bar when the scene is hidden and route durations on the flight map, shared by all your characters. In both, your bags and the world map open above the scene with their usual keys

**Configuration**
- **Default Settings:** keeps auto loot on, loots faster and sets up new characters
- **Profiles:** options, active modules and window positions, saved as you change them and shared by the characters using the same profile; give one to your new characters, or export it as a text to share
- **Minimap Button:** quick access and customizable clicks

## Moving windows

The addon's windows are moved in the game's Edit Mode (`/edit`): Class Bar, Buffs and Thanks, Potion Reminder, Stat Changes, the loot of Immersion Mode, the check-up and its chat button. They snap to the grid and to the other frames, and a click opens their settings. Changes are saved at once, apart from the Edit Mode layouts.

## Optional addons

Install **What's Training?** to see the spells to learn from your class trainer, and their total cost, in the level-up panel. Without it, the panel only shows your stats.

## Commands

| Command | Effect |
|---|---|
| `/tw` or `/tinkerwise` | Opens the configuration |
| `/rl` | Reloads the interface |
| `/edit` | Opens Blizzard's Edit Mode, where the addon's windows can be moved too |
| `/kb` | Opens Blizzard's Quick Keybind Mode |
| `/cc` | Opens or closes the Click Casting window |
| `/tw checkup` | Runs the check-up |
| `/tw chars` | Shows My Characters: level, gold, rest, bags and banks of your characters |
| `/tw groups` | Manages the groups of My Characters |
