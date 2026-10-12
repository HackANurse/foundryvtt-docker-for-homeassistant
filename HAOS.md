# Foundry VTT 14 su Home Assistant OS

![Foundry VTT HAOS](foundryvtt/logo.png)

> [!IMPORTANT]
> **Add-on non ufficiale e non affiliato a Foundry Gaming LLC, al progetto `felddy/foundryvtt-docker` o a Home Assistant.**

Questo progetto consente di eseguire Foundry Virtual Tabletop 14 su Home Assistant OS usando l'immagine [`ghcr.io/felddy/foundryvtt:14`](https://github.com/felddy/foundryvtt-docker).

Il repository è un fork di [`felddy/foundryvtt-docker`](https://github.com/felddy/foundryvtt-docker). La cronologia, la licenza MIT e l'attribuzione del progetto originale sono conservate; l'adattamento HAOS si trova nella cartella [`foundryvtt`](foundryvtt/).

Questo progetto installa Foundry come add-on gestito dal Supervisor di Home Assistant. Non rimuove né sostituisce HAOS e non richiede di installare o gestire Docker manualmente sull'host.

## Sostieni il progetto

[![Sostieni FoundryOnHAOS su Buy Me a Coffee](https://img.buymeacoffee.com/button-api/?text=Supporta+il+progetto&emoji=%E2%98%95&slug=andybegh&button_colour=FFDD00&font_colour=000000&font_family=Lato&outline_colour=000000&coffee_colour=ffffff)](https://www.buymeacoffee.com/andybegh)

Le donazioni sostengono esclusivamente lo sviluppo e la manutenzione dell'adattamento **FoundryOnHAOS**. Non costituiscono l'acquisto di Foundry Virtual Tabletop e non includono software Foundry, chiavi di licenza, accesso a server o servizi di hosting.

## Funzioni

- dati persistenti di Foundry in `/config`;
- cartelle HAOS `media` e `share` disponibili nel file picker di Foundry;
- porta esterna modificabile dalla UI di Home Assistant;
- cache persistente del pacchetto Foundry;
- aggiornamenti di Foundry installabili dalla sua interfaccia web e conservati ai riavvii;
- download forzato solo quando richiesto;
- esecuzione di Foundry come utente `node` con UID/GID `1000:1000`;
- configurazione e dati inclusi nei backup a freddo dell'add-on.

## Requisiti

- **Home Assistant OS** con Supervisor e App Store;
- architettura `amd64` oppure `aarch64`;
- account e licenza Foundry VTT validi;
- connessione Internet per il download iniziale e gli aggiornamenti;
- spazio sufficiente per applicazione, cache, mondi e asset.

Non è richiesta né prevista l'installazione manuale di Docker sull'host. Home
Assistant Container e Home Assistant Core non possono installare Apps/add-on.
Home Assistant Supervised è un metodo legacy non più supportato ufficialmente da
Home Assistant dalla versione 2025.12: l'add-on può funzionare su installazioni
Supervised preesistenti dotate di Supervisor, ma tale configurazione non è un
target supportato da questo progetto. Per un'installazione supportata usa Home
Assistant OS.

## Installazione dal repository

[![Aggiungi il repository a Home Assistant](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2FHackANurse%2Ffoundryvtt-docker-for-homeassistant)

Seleziona il pulsante qui sopra per aprire il tuo Home Assistant e aggiungere automaticamente il repository. In alternativa:

1. Apri **Impostazioni → Apps → Installa app** in Home Assistant (nelle versioni precedenti: **Add-on Store**).
2. Apri il menu in alto a destra e scegli **Repository**.
3. Aggiungi `https://github.com/HackANurse/foundryvtt-docker-for-homeassistant`.
4. Aggiorna la pagina, apri **Foundry VTT HAOS** e seleziona **Installa**.
5. Compila le opzioni dell'add-on e avvialo.

## Installazione locale su HAOS

 Copia la cartella `foundryvtt` di questo progetto in:

```text
/addons/foundryvtt
```

Puoi trasferire i file con un add-on gestito da Home Assistant, per esempio Studio Code Server, Samba share o Terminal & SSH. Poi ricarica gli add-on locali dal menu dell'Add-on Store e installa **Foundry VTT HAOS**. Anche in questo caso il ciclo di vita resta interamente gestito da HAOS: non avviare container Docker manualmente.

## Configurazione

È necessario fornire uno dei due metodi di download:

- `foundry_username` e `foundry_password`; oppure
- `foundry_release_url`, usando un URL temporaneo per il pacchetto **Node.js** ottenuto dal sito Foundry VTT.

Opzioni disponibili:

| Opzione | Valore iniziale | Descrizione |
| --- | --- | --- |
| `foundry_username` | vuoto | Username o email dell'account Foundry VTT. |
| `foundry_password` | vuoto | Password dell'account Foundry VTT. |
| `foundry_release_url` | vuoto | URL temporaneo alternativo alle credenziali. |
| `foundry_admin_key` | vuoto | Chiave di accesso alla schermata amministrativa. |
| `foundry_license_key` | vuoto | Chiave licenza; può anche essere inserita dalla UI di Foundry. |
| `foundry_telemetry` | `false` | Abilita o disabilita la telemetria Foundry. |
| `container_preserve_config` | `true` | Non sovrascrive `Config/options.json` e `Config/admin.txt` se esistono. |
| `force_download` | `false` | Elimina dalla cache il pacchetto della versione corrente e lo scarica di nuovo al prossimo avvio. |

Non inserire credenziali o chiavi direttamente nei file del repository. Salvale esclusivamente nella scheda **Configurazione** dell'add-on.

## Porta di rete

Foundry ascolta sulla porta interna `30000`. Nella scheda **Configurazione → Rete** dell'add-on puoi cambiare la porta pubblicata sull'host senza modificare alcun file. Il pulsante **Apri interfaccia web** usa automaticamente la porta scelta.

## Dati persistenti

L'add-on usa `/config` come `dataPath` di Foundry. HAOS monta in quel percorso la cartella `addon_config` dedicata all'add-on. La struttura creata è:

```text
/config/
├── Backups/
├── Config/
├── Data/
│   └── assets/
│       ├── haos-media -> /media
│       └── haos-share -> /share
├── Logs/
├── container_cache/
└── foundry_app/
```

Nel file picker di Foundry i contenuti condivisi sono disponibili in:

```text
Data/assets/haos-media
Data/assets/haos-share
```

All'avvio, l'add-on assegna i file persistenti a UID/GID `1000:1000`, usati dall'utente `node` dell'immagine Foundry, e concede lettura/scrittura a proprietario e gruppo.

## Cache e aggiornamenti di Foundry

Il pacchetto scaricato viene conservato in:

```text
/config/container_cache
```

Con `force_download: false`, se la cache contiene il pacchetto esatto richiesto dall'immagine `:14`, le credenziali e l'URL non vengono passati al downloader. In caso di nuova build Foundry 14, il primo avvio scarica una volta il pacchetto aggiornato e lo conserva; i riavvii successivi usano la cache.

L'installazione applicativa si trova in `/config/foundry_app`. L'add-on non usa
`--noupdate`: dalla schermata **Aggiornamento software** di Foundry puoi quindi
scaricare e installare un aggiornamento, che resta disponibile anche dopo il
riavvio dell'add-on.

Prima di aggiornare crea un backup completo dell'add-on e arresta i mondi attivi.
Installa dalla UI soltanto aggiornamenti compatibili con la generazione 14: per
passare a una nuova generazione serve una versione dell'add-on basata sulla
corrispondente immagine `felddy`, perché possono cambiare Node.js e le dipendenze
di sistema.

Per riscaricare intenzionalmente la versione corrente:

1. imposta `force_download: true`;
2. riavvia l'add-on e attendi il completamento del download;
3. reimposta `force_download: false`.

Se usi `foundry_release_url`, genera un nuovo URL temporaneo prima di forzare il download.

`force_download: true` elimina anche l'installazione applicativa persistente e
ripristina la versione prevista dall'immagine dell'add-on. Usalo quindi come
procedura di recupero o reinstallazione intenzionale, non per un normale riavvio.

## Aggiornamento dell'add-on

Dopo un aggiornamento del repository, usa il pulsante **Aggiorna** nella pagina dell'add-on. Se hai installato la cartella come add-on locale, sostituisci i file, ricarica gli add-on locali e scegli **Aggiorna**. Home Assistant può richiedere una nuova compilazione dell'immagine.

Prima di aggiornare, crea un backup dell'add-on. I dati persistenti si trovano nell'`addon_config` assegnato da HAOS; il prefisso della cartella dipende dal metodo di installazione e dal repository.

## Log e problemi comuni

Controlla i log dalla scheda **Log** dell'add-on.

- **Cache assente:** configura credenziali oppure un URL temporaneo valido.
- **URL scaduto:** genera un nuovo URL Node.js e salvalo nelle opzioni.
- **Permessi:** l'avvio riallinea automaticamente `/config` a `1000:1000`.
- **Link `haos-media` o `haos-share` già esistente come cartella:** per sicurezza l'add-on non lo sovrascrive; rinomina la cartella e riavvia per creare il link.
- **Porta occupata:** cambia la porta pubblicata nella sezione **Rete** dell'add-on.

## Avvertenze

Questo add-on è sperimentale e non ufficiale. Richiede una licenza Foundry VTT valida. Esegui sempre un backup prima di aggiornare Foundry, l'add-on o Home Assistant OS.

## Sviluppo assistito da AI

Parte dell'adattamento per Home Assistant OS e della relativa documentazione è
stata sviluppata con il supporto di OpenAI Codex. Tutte le modifiche sono state
revisionate, verificate e approvate dal maintainer, che resta responsabile dei
contenuti pubblicati.

## Licenza e attribuzioni

Il codice di questo adattamento HAOS è distribuito con licenza MIT. Il progetto usa l'immagine [`ghcr.io/felddy/foundryvtt:14`](https://github.com/felddy/foundryvtt-docker), il cui progetto originale è distribuito con licenza MIT e attribuito a Mark Feldhousen.

Foundry Virtual Tabletop è software proprietario di Foundry Gaming LLC, non è incluso nella licenza MIT di questo repository e richiede una licenza Foundry valida. Consulta il file [`LICENSE`](LICENSE) per il testo completo, le attribuzioni e i termini applicabili.
