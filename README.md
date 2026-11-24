# Tinkerwise

Boîte à outils personnelle pour WoW Forever : des modules indépendants, à activer ou désactiver dans une seule fenêtre de configuration.
L'interface est disponible en anglais et en français, selon la langue du jeu. Les autres langues affichent l'anglais.

## Installation

Copiez le dossier dans `World of Warcraft\_forever_\Interface\AddOns\`. Il doit s'appeler exactement `Tinkerwise`. Relancez ensuite le jeu.

## Commandes

| Commande | Effet |
|---|---|
| `/tw` ou `/tinkerwise` | Ouvre la configuration |
| `/rl` | Recharge l'interface (comme `/reload`) |
| `/edit` | Ouvre le mode Édition du jeu, où les fenêtres de l'addon se déplacent aussi |
| `/kb` | Ouvre le mode de raccourcis rapides de Blizzard |
| `/cc` | Ouvre ou ferme la fenêtre des sorts à la souris |
| `/tw checkup` | Lance le check-up |
| `/tw chars` | Affiche Mes personnages : niveau, or, repos, sacs et banques de vos personnages |
| `/tw groups` | Gère les groupes de Mes personnages |

## Modules

Par section de la fenêtre `/tw` :

- **Préparation :** Check-up, Rappel potion
- **Personnage :** Mes personnages, Changements de stats, Barre de classe
- **Objets :** Infobulles d'objets (comparaison et liens Wowhead), Vendeur automatique
- **Groupe :** Confort de groupe, Buffs et remerciements, Provisions en échange
- **Tchat :** Tchat
- **Interface :** Thème sombre, Apparence (fenêtres de Tinkerwise en or ou aux couleurs de la classe), Cadres de joueurs, Barres d'info, Minimap, Éléments d'interface (minimenu, sacs, suivi des quêtes et messages d'erreur)
- **Immersion :** Mode immersion (avec la scène de quête), Modes AFK et vol
- **Configuration :** Réglages par défaut, Bouton de la minicarte

## Déplacer les fenêtres

Les fenêtres de l'addon se déplacent dans le mode Édition du jeu (`/edit`) : Barre de classe, Buffs et remerciements, Rappel potion, Changements de stats, butin du mode immersion, Check-up et son bouton au-dessus du tchat. Elles s'accrochent à la grille et aux autres éléments quand la case d'accrochage est cochée. Un clic ouvre leurs réglages et le bouton pour réinitialiser leur position. Ces changements sont enregistrés tout de suite : ils ne font pas partie des profils du mode Édition et « Annuler » n'a pas d'effet dessus.

## Détails

Barre de classe montre les sorts utilitaires de votre classe sous forme de barre d'action, avec les réglages d'une barre du jeu (orientation, lignes, taille, visibilité...), un sens d'extension et une case par bouton et par sort. En démoniste, elle compte les fragments d'âme, et le bouton de pierre d'âme utilise la pierre des sacs ou en crée une. Les guerriers n'ont rien à y afficher.

Provisions en échange (mages et démonistes) remplit la fenêtre d'échange, sans jamais l'accepter. Par défaut, seulement pour votre groupe.

Changements de stats affiche aussi un résumé à chaque niveau gagné. Pour y voir les sorts à apprendre au maître de classe, installez l'addon [What's Training?](https://www.curseforge.com/wow/addons/whats-training). Sans lui, le résumé n'affiche que les stats.

Mes personnages classe vos personnages par mode de jeu (PvE, PvP, Hardcore, RP, RP-PvP, détecté automatiquement) et par groupes que vous créez, par exemple « PvE - Groupe par défaut » et « PvE - Guilde ». Les infobulles ne comptent que le groupe courant, et les fenêtres l'affichent par défaut, avec un menu pour consulter les autres. Le module s'active par personnage.

## Réglages

Les réglages sont enregistrés par personnage, sauf ceux d'Apparence, de Réglages par défaut et de Mes personnages, communs au compte, comme les durées de vol apprises. Tous les modules sont activés par défaut : désactivez ceux dont vous ne voulez pas dans `/tw`. Sa fenêtre affiche une page par section, un onglet par module et une recherche qui retrouve n'importe quel réglage. Apparence, Réglages par défaut et Bouton de la minicarte restent toujours actifs.

## Licence

Voir [LICENSE](LICENSE).
