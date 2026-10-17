# Architektur und Protokoll

`v2/main.lua` startet alle Rollen. `store.lua`, `net.lua`, `nav.lua` und `inventory.lua` bilden die gemeinsame Laufzeit; `jobs.lua` plant die Front, `coordinator.lua` und `worker.lua` steuern die Rollen. Module werden relativ zum aktiven Release geladen. Konfiguration und Zustand liegen ausserhalb der Releases.

## Nachrichten

Rednet-Protokollname `flotte_v2`; Tabellen mit `version=2`, `fleet`, `from`, `session`, `id`, `kind`, `payload`. `from` muss mit dem tatsaechlichen Rednet-Absender uebereinstimmen. Sessions sind persistente Bootzaehler. Anfrage-IDs enthalten Computer-ID, Session und persistenten Nachrichtenzaehler. Antworten enthalten `kind=REPLY` und `payload={replyTo,ok,data,error}`. Antworten werden nur fuer eine ausstehende Anfrage an genau diesen Absender angenommen.

RPC wiederholt dieselbe Anfrage-ID mit versetzten Intervallen. Aendernde Anfragen erhalten dauerhaft gespeicherte Antworten (bis 512); zusaetzliche fachliche Kennungen schuetzen aktive Aufgaben und Uebergaben gegen Wiederholung. Lesende Abfragen werden frisch beantwortet. Flottenkennungen trennen Flotten, sind aber kein kryptographischer Schutz gegen andere Spieler mit Zugriff auf das Funknetz.

- `HELLO`: nur erwartete beziehungsweise bereits registrierte Arbeiter; Positions-/Sitzungsabgleich, Parkplatz und Anfangsausrichtung.
- `POLL`, `ACCEPT`, `DONE`, `PROBLEM`, `CANCELLED`: eindeutige Teilaufgaben, explizite Annahme und bestaetigte Beendigung. Beobachtung und Abbau desselben Blocks besitzen unterschiedliche IDs.
- `RESERVE`, `ARRIVED`, `ROUTE`: Freigabe genau eines benachbarten Schritts, Bestaetigung tatsaechlicher Ankunft und Wegsuche. Quell-/Zielposition bleiben bis zur Bestaetigung geschuetzt. Bei Neustart wird eine offene Bewegung mit GPS abgeglichen.
- `HEARTBEAT`: alle fuenf Sekunden; Sequenznummern verhindern das Wiederaufleben alter Bedarfe. Ohne Kontakt nach 20 Sekunden bleiben Positionen gesperrt.
- `SERVICE`, `SERVICE_STATUS`, `SERVICE_COMMIT`, `SERVICE_CLOSE`: vorbereiten, bereitmelden, physisch uebertragen, pruefen, bestaetigen und freigeben. Beide Seiten pruefen die Computer-ID am Nachbarblock. Kohlelieferungen brauchen einen bestaetigten Treibstoffanstieg.
- `COMMAND`, `CONTROL`, `STATUS`: Bedienung und Rueckmeldungen. Abbruch wird erst nach Stillstand des Arbeiters bestaetigt; seine Aufgabe wird vorher nicht freigegeben.
- `PACK_READY`: der leere Arbeiter bestaetigt seinen Parkplatz und nimmt bis zum Abschalten keine weitere Arbeit an.

## Arbeit und Wege

Der Verwalter arbeitet eine persistente Hauptauftragswarteschlange ab. Arbeitsfronten bestehen aus einzelnen Zielbloecken. Fuer jeden Auftrag muessen ein erreichbarer freier Arbeiterstandplatz und ein erreichbarer benachbarter Serviceplatz existieren. Unbekannte Bloecke werden zuerst inspiziert; der passende Beruf wird danach gewaehlt. Beobachtungen angrenzender Zellen erweitern die Karte. Selektive Auftraege dokumentieren ausgelassene Materialien.

Wegsuche verwendet ausschliesslich bekannte Luftzellen. Der Verwalter kann begrenzt freie Umgebung erkunden, ohne zu graben (maximal 4096 Schritte je Fahrt, BFS maximal 16384 Zellen). Arbeitsquader sind auf 32768 Zellen beschraenkt. Arbeitsaufgaben, belegte Positionen und offene Bewegungen werden beruecksichtigt. Arbeiter lassen bei Bedarf eine neue Route berechnen und parken, wenn sie sonst den Zugang anderer Berufe blockieren wuerden.

Inventare, Computer, Turtles, Spawner, Fluessigkeiten und Bedrock werden nicht als normale Arbeitsbloecke freigegeben. Zusaetzliche Modbloecke sind ueber `blockRoles` konfigurierbar; geschuetzte Namen haben Vorrang. Es werden keine Entities angegriffen. Nicht loesbare Hindernisse blockieren nachvollziehbar den Auftrag.

## Persistenz

`.flotte/state`, `.bak` und `.next` enthalten Sequenznummer, serialisierten Inhalt und Pruefsumme. Beim Laden gewinnt die hoechste gueltige Generation. Sind alle vorhandenen Generationen beschaedigt, wird kein leerer Zustand erfunden. Vor Bewegungen, Drehungen, Transfers, Crafting und Turtle-Lebenszyklusaktionen wird ein Intent geschrieben.

Mengenbuchungen fuer ausgehende Lagerungen, Zutatenaufnahme und Kohle-/Zutatenuebergaben werden innerhalb derselben bestaetigten Generation wie der physische Abschluss gespeichert. Nach unterbrochenen Transfers ergibt sich die lokale Mengenaenderung aus Vorherinventar und tatsaechlichem Inventar. Abholungen sind ueber eine stabile Uebergabe-ID und die Inventardifferenz des Verwalters abgesichert. Aussetzen und Einsammeln besitzen zusaetzliche persistente Zwischenphasen.

Dateisystemzugriff wird vor physischen Aktionen benoetigt. Speicherplatz muss fuer mehrere Generationen reichen; die erforderliche Groesse waechst mit Karte und Berichten. Bei grossen Auftraegen die CC-Speichergrenze ausreichend konfigurieren. Alte Berichte werden nicht automatisch geloescht.

## Crafting

Ein Task entspricht genau einem Rezeptvorgang. Der Verwalter holt die registrierten Zutatenmengen aus sortenreinen Quellen. Arbeiterinventare werden vor der Zutatenausgabe geleert. Die 3x3-Zellen werden auf Turtle-Slots 1,2,3,5,6,7,9,10,11 abgebildet. Ausgabe und Restgegenstaende werden gegen das registrierte Rezept geprueft; Erfolg wird nicht allein aus `turtle.craft` abgeleitet. Unklare Ergebnisse werden nicht erneut gefertigt.
