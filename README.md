# 🧙 Hex Wizard TD — Deckbuilding & Tower Defense (Godot 4.7)

Un jeu hybride **Tower Defense / Deckbuilding** au tour par tour sur un plateau hexagonal (côté 7 tuiles, 127 hexagones), développé avec **Godot 4.7**.

## 🎮 Concept du Jeu
- **La Tour du Sorcier** se trouve au centre du plateau `(0, 0)`.
- **Les Monstres** apparaissent sur la bordure extérieure à chaque tour et avancent vers la tour. Leur nombre et leur puissance augmentent au fil des vagues et des apparitions. Chaque monstre possède une **Faiblesse élémentaire (dégâts ×2)** et une **Résistance élémentaire (dégâts ×0.5)** et rapporte **+1 Or** lorsqu'il est vaincu.
- **Création de Sorts en Éventail (3 Cartes)** :
  Chaque carte possède **2 composants** séparés par une diagonale. Pour lancer un sort, vous assemblez **3 cartes dans l'ordre** :
  1. **ÉLÉMENT** : *Neutre (11 DG)*, *Feu (18 DG)*, *Glace (11 DG + Gel)*, *Poison (9 DG + Poison)*, *Terre (13 DG + Repousse)* — ou *5 DG par défaut* si la carte n'a pas d'Élément.
  2. **FORME (Gabarit)** : *Petits gabarits de 3 hexagones (Ligne, V, Triangle)* ou *Grands gabarits de 7 hexagones (Ligne, Hexagone, Triangle+1, Zigzag)* — ou *1 Hexagone par défaut* si la carte n'a pas de Forme.
  3. **BONUS** : *+1 Hex Aléatoire*, *+10% Dégâts*, *+1 Pièce d'Or*, *Acheter Carte*, *+25% Dégâts*, *Piocher +1*, *Gabarit +3 Hex*, *Repousse +2*, *Soin Tour*, *Fragilise*, *Reste 1 Tour* — ou *Aucun bonus* si la carte n'a pas de Bonus.
- **Marché Arcanique** :
  - Cartes à 1 composant puissant (`★`) : **3 Or** (80 % de probabilité).
  - Cartes à 2 composants puissants (`★★`) : **8 Or** (20 % de probabilité).
  - Possibilité de supprimer une offre du marché (**1 Or + 1 Achat**) ou de retirer définitivement une carte de son Deck (**2 Or**, puis le coût double à chaque retrait : 4, 8, 16...).

## 🚀 Lancer le projet
1. Ouvrez **Godot 4.7**.
2. Importez le fichier `project.godot`.
3. Appuyez sur **`F5`** pour jouer !
