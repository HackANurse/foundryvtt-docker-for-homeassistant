# Documentazione di Foundry VTT HAOS

> **Questo è un add-on non ufficiale.** Non è affiliato a Foundry Gaming LLC, al progetto `felddy/foundryvtt-docker` o a Home Assistant.

## Prima configurazione

Fornisci uno dei due metodi di download nella scheda **Configurazione**:

- `foundry_username` e `foundry_password`; oppure
- `foundry_release_url`, usando un URL temporaneo per il pacchetto Node.js ottenuto dal sito Foundry VTT.

Puoi inserire la licenza tramite `foundry_license_key` oppure dalla UI di Foundry. Non pubblicare mai credenziali, URL temporanei o chiavi di licenza nel repository.

## Porta di rete

Foundry ascolta internamente sulla porta `30000`. La porta pubblicata sull'host è modificabile dalla sezione **Rete** dell'add-on senza cambiare i file.

## Dati persistenti

Il percorso dati è `/config`, collegato da HAOS all'`addon_config` dell'add-on:

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

All'avvio i file ricevono proprietario e gruppo `1000:1000`, usati dall'utente `node` dell'immagine Foundry.

## Cache e download

Con `force_download: false`, i riavvii usano il pacchetto conservato in `/config/container_cache`. Per scaricare nuovamente la versione corrente:

1. imposta `force_download: true`;
2. riavvia l'add-on e attendi il download;
3. reimposta `force_download: false`.

Se utilizzi `foundry_release_url`, genera un nuovo URL temporaneo prima di forzare il download.

## Aggiornamento manuale a una build scelta

Prima di aggiornare crea un backup completo e arresta tutti i mondi. Nella
scheda **Configurazione** puoi richiedere un singolo aggiornamento con:

- `foundry_target_version`, per esempio `14.370`;
- `foundry_release_url`, usando un nuovo URL temporaneo Node.js;
- `install_target_version: true`, che avvia l'operazione una sola volta.

Le combinazioni ammesse sono:

- **versione e URL:** l'URL fornisce l'archivio, che deve corrispondere
  esattamente alla versione indicata;
- **solo versione:** l'add-on usa `foundry_username` e `foundry_password` per
  ottenere il pacchetto esatto;
- **solo URL:** la versione viene ricavata e verificata dall'archivio.

L'add-on scarica ed estrae la nuova applicazione in un'area temporanea. Soltanto
dopo la verifica promuove la nuova installazione, mantenendo quella precedente
per il primo avvio. Se Foundry termina o non apre la porta entro 180 secondi,
l'add-on ripristina automaticamente la versione precedente. `Data`, `Config`,
`Backups` e `Logs` non vengono spostati o cancellati.

Dopo un aggiornamento riuscito riporta `install_target_version` a `false`. Se
rimane accidentalmente attivo, lo stato completato impedisce di ripetere lo
stesso download ai riavvii. Gli URL temporanei possono scadere: generarne uno
nuovo prima di ogni richiesta.

Se il primo avvio fallisce, l'add-on non ritenta automaticamente: imposta
`install_target_version: false`, salva e avvia una volta per azzerare lo stato;
correggi URL o versione e riattiva poi il comando.

Sono accettate soltanto build della generazione 14. Per una nuova generazione
attendi un aggiornamento dell'add-on basato sull'immagine `felddy` compatibile.

## Aggiornamenti dalla UI di Foundry

L'add-on lascia attiva la schermata **Aggiornamento software** di Foundry e
conserva l'applicazione in `/config/foundry_app`. Un aggiornamento installato
dalla UI resta quindi disponibile dopo il riavvio dell'add-on.

Prima di procedere crea un backup completo e arresta i mondi attivi. Aggiorna
soltanto all'interno della generazione 14; per una nuova generazione attendi una
versione dell'add-on basata sull'immagine `felddy` compatibile.

L'opzione `force_download: true` **non installa la versione più recente**:
rimuove l'applicazione persistente e reinstalla la versione fornita
dall'immagine dell'add-on. Non attivarla insieme a `install_target_version` e,
dopo una reinstallazione, riportala a `false`.

## Cartelle condivise

Nel file picker di Foundry trovi:

```text
Data/assets/haos-media
Data/assets/haos-share
```

## Backup e aggiornamenti

Prima di aggiornare Foundry, l'add-on o Home Assistant OS crea un backup. L'add-on usa backup a freddo: Home Assistant lo arresta durante il salvataggio dei dati.

## Supporto e licenze

Segnala problemi nel [repository GitHub](https://github.com/HackANurse/foundryvtt-docker-for-homeassistant/issues).

Le donazioni sostengono esclusivamente lo sviluppo dell'adattamento HAOS e non includono software Foundry, licenze, hosting o accesso a server. Foundry Virtual Tabletop è software proprietario e richiede una licenza valida.
