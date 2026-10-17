# Turtle-Flotte v2

Eine CC:Tweaked-Flotte mit Taschencomputer, mobiler Verwalter-Turtle und spezialisierten Arbeitern. Der Verwalter setzt vorinstallierte Arbeiter aus, verteilt Teilaufgaben, bringt ihnen Kohle, holt ihre Gegenstaende ab und sammelt die Arbeiter wieder ein.

## Voraussetzungen

- CC:Tweaked **ab 1.116.0** mit `turtle.getEquippedLeft/Right`, GPS und Funkmodems. Der Starttest prueft die tatsaechlich vorhandenen APIs und Werkzeuge.
- Verwalter: beschriftete Turtle mit Diamantspitzhacke und Funkmodem.
- Arbeiter: jeweils Funkmodem und genau ein Werkzeug: Diamantspitzhacke, Diamantschaufel, Diamantaxt oder Werkbank. Jede Turtle mit `label set <name>` beschriften; Beschriftung erhaelt beim Abbauen Computer-ID und gespeicherte Programme.
- Basis, Arbeitsgebiet und alle Verbindungswege bleiben geladen und haben Funk-/GPS-Abdeckung. Kein Chunkloading durch dieses Programm.
- Normale Truhen fuer Start, Kohle und Ausgabe; Craftingzutaten je Item in einer eigenen sortenreinen Truhe. Mekanism ist nicht erforderlich.
- HTTP-Zugriff auf `api.github.com` und `raw.githubusercontent.com` fuer Installation/Updates. Laufender Betrieb benoetigt kein Internet.

## Installation

Auf jedem Geraet:

```lua
wget https://raw.githubusercontent.com/TeutonStudio/Turtle-Flotte-CC-/master/init.lua init.lua
init.lua
reboot
```

Der Installer laesst die Rolle auswaehlen. Er loest zuerst einen Git-Commit auf, laedt alle Dateien genau dieses Commits in ein separates Releaseverzeichnis, prueft Laenge, Pruefsumme und Lua-Syntax und schaltet erst danach um. Die Pruefsumme dient der Downloadintegritaet, nicht der Authentifizierung; Downloads erfolgen ueber HTTPS. Bestehende v1-Dateien werden gesichert, laufende v1-Auftraege nicht importiert.

Vor dem Merge kann der Entwicklungsbranch installiert werden:

```lua
wget https://raw.githubusercontent.com/TeutonStudio/Turtle-Flotte-CC-/codex/flotte-v2/init.lua init-v2.lua
init-v2.lua codex/flotte-v2
reboot
```

Updates: `flotte-update`. Ein optionales Ref-Argument waehlt einen anderen Branch/Commit, beispielsweise `flotte-update master`. Ein Update wird bei laufender Arbeit oder ungeklaerten physischen Vorgaengen abgewiesen. Konfiguration und Zustand unter `.flotte/` werden erhalten. Die bisherige Releaseadresse steht in `.flotte/active.bak`.

## Basis einrichten

1. Verwalter an die gewuenschte Basis stellen, manuell etwas Kohle tanken und die Blickrichtung kennen. Der Block davor muss fuer die Richtungskalibrierung frei sein.
2. Beim ersten Start den Assistenten ausfuellen. Spaetere Aenderungen mit `flotte einrichten` **lokal auf dem jeweiligen Geraet**, nachdem alle Auftraege beendet und Arbeiter eingelagert sind.
3. Fuer jede Truhe den **Standplatz der Turtle**, deren Blickrichtung und die Uebergabeseite `front`, `up` oder `down` eintragen. Niemals die Blockposition der Truhe als Standplatz verwenden.
4. Einen Aussetzstandplatz mit `front` sowie einen eigenen Parkplatz pro Arbeiter einrichten (1–8). Parkplaetze muessen Truhenzugaenge, Aussetzplatz und Fahrwege freilassen.
5. Alle Standplaetze durch freie Wege verbinden. Vor dem Aussetzplatz muss Platz zum Wegfahren sein. Arbeitsgebiete brauchen einen freien Zugang oberhalb ihrer kleinsten X/Z-Ecke und erreichbare Serviceplaetze neben den Arbeitsstandorten. Navigation graebt keine beliebigen Anfahrtswege durch die Umgebung.
6. Arbeiter einzeln installieren, beschriften und deren Verwalter-ID/Flottenkennung einrichten. Danach abschalten, abbauen und in die Starttruhe legen. In die Kohletruhe ausschliesslich Kohle/Holzkohle legen. Das Ergebnislager muss freie Plaetze haben.
7. Taschencomputer installieren und dieselbe Flottenkennung sowie die Computer-ID des Verwalters eintragen.

Ein Auftrag setzt alle verfuegbaren Arbeiter bis zur konfigurierten Zahl aus. Fehlende Berufe werden als Blockierung sichtbar. Nach Abbauaufgaben ohne weitere passende Arbeit verlassen Arbeiter die Arbeitsfront und parken, damit andere Berufe Zugang erhalten.

## Befehle auf dem Taschencomputer

```text
flotte list
flotte status
flotte abbau von:100,64,100 bis:102,62,102
flotte erdarbeiten von:100,64,100 bis:102,64,102
flotte holz von:100,64,100 bis:110,80,110
flotte rezepte name:bretter datei:bretter.json
flotte craft rezept:bretter menge:16
flotte pause
flotte weiter
flotte abbrechen
flotte bericht id:<ausgegebene-job-id>
```

Optionales `id:<verwalter-id>` adressiert bei Arbeits-/Statusbefehlen einen anderen Verwalter derselben Flottenkennung. `bericht id:<job-id>` fragt den eingerichteten Verwalter ab.

- **Abbau:** Quader mit Spitzhacke, Schaufel und Axt gemeinsam raeumen. Materialzuordnung ueber Blocktags, Vanilla-Zuordnungen und optionale `blockRoles` in der Konfiguration.
- **Erdarbeiten:** Nur Bodenmaterialien im Quader entfernen; andere erkannte Materialien stehenlassen.
- **Holz:** Nur Holz/Blaetter im Quader entfernen. Kein Nachpflanzen und kein Verfolgen von Aesten ausserhalb der Grenzen.
- **Crafting:** Vorhandene Zutaten verwenden; keine rekursive Rohstoffproduktion. Rezeptmengen muessen durch die Ausgabemenge teilbar sein. Vorlage: [examples/bretter.json](examples/bretter.json). Die neun Rasterzellen enthalten Item-IDs oder `false`; `returns` beschreibt alle Restgegenstaende pro Craftingvorgang. Fuer Behaelterrezepte beispielsweise `{"minecraft:bucket": 1}` eintragen.

`pause` stoppt neue Arbeit; Versorgung bleibt moeglich. `abbrechen` beendet die Arbeit kontrolliert, holt Gegenstaende ab und sammelt die Arbeiter ein. Fehlende Kohle kann auch einen Rueckruf blockieren. Ein Auftrag wird erst nach Einlagerung der Ausgabe **und** aller Arbeiter erfolgreich abgeschlossen.

## Fehler und Wiederaufnahme

Leere Kohletruhen, fehlende Zutaten und volle Ausgabetruehen werden regelmaessig erneut geprueft. Nachfuellen beziehungsweise Platz schaffen reicht normalerweise aus. Bei Arbeits-/Navigationsfehlern Ursache beheben und `flotte weiter` senden. GPS-/Funkverlust fuehrt zu einem Wartezustand; nach 20 Sekunden ohne Arbeiterkontakt bleiben dessen Positionen reserviert. Bereich niemals gleichzeitig einer Ersatz-Turtle zuweisen.

Vor jeder physischen Aktion wird ein Intent gespeichert. Neustarts gleichen Positionen, Uebergabemengen und eindeutige Craftingergebnisse ab. Unklare Faelle werden blockiert statt blind wiederholt. Weitere Hinweise: [docs/RECOVERY.md](docs/RECOVERY.md).

## Entwicklung und Abnahme

```sh
lua tests/run.lua
python3 tools/build_manifest.py
```

Die Simulation fuehrt die echten v2-Module auf mehreren simulierten Computern mit Inventaren, Rednet, GPS und persistentem Dateisystem aus. Sie prueft auch Paketverlust, doppelte Pakete und Unterbrechungen zwischen physischer Aktion und Zustandsbuchung. CI prueft Lua-Syntax und das generierte Downloadmanifest.

Die Minecraft-Abnahme ist separat erforderlich; eine Simulation ersetzt insbesondere die Pruefung der modpackspezifischen Werkzeuge, Itemdetails, Schutzplugins und Chunkgrenzen nicht. Testprotokoll: [docs/ABNAHME.md](docs/ABNAHME.md). Architektur und Protokoll: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

Die alten rollenbezogenen Verzeichnisse enthalten weiterhin v1-Hilfsmodule fuer historische Referenz. Ihre Start- und Update-Einstiegspunkte leiten auf v2 um. Der v2-Installer installiert ausschliesslich das neue `v2/`-Paket; keine v1-Laufzeitmodule werden geladen.
