# Aggiornamento manuale e transazionale di Foundry VTT

Data: 2026-11-13  
Stato: proposta da approvare

## Intento

Consentire al maintainer dell'istanza di installare deliberatamente una specifica
build di Foundry VTT 14 oppure una build ricavata da un URL temporaneo, senza
confondere questa operazione con `force_download` e senza eliminare
l'installazione funzionante prima di avere validato quella nuova.

## Obiettivi

- Aggiornamento esclusivamente manuale e una tantum.
- Supporto combinato a versione obiettivo esplicita e URL temporaneo.
- Nessuna ricerca o installazione automatica dell'ultima release a ogni avvio.
- Verifica dell'archivio prima di modificare l'applicazione persistente.
- Conservazione completa di `/config/Data`, `/config/Config`, backup e log.
- Ripetibilità sicura: un riavvio non deve reinstallare la stessa versione.
- Messaggi di log chiari senza mostrare credenziali o URL firmati.

## Non obiettivi

- Aggiornare automaticamente a una nuova generazione di Foundry.
- Aggiornare o sostituire Home Assistant OS.
- Avviare Docker manualmente sull'host.
- Garantire la compatibilità di sistemi e moduli di terze parti.
- Trasformare `force_download` nel comando di avanzamento versione.

## Interfaccia proposta

Nuove opzioni dell'add-on:

```yaml
foundry_target_version: ""
install_target_version: false
```

`foundry_release_url` continua a essere usato come sorgente opzionale.
`force_download` resta riservato alla reinstallazione della versione prevista
dall'immagine corrente.

## Regole di selezione

Quando `install_target_version: false`, l'avvio resta invariato.

Quando `install_target_version: true`:

1. Se sono presenti versione e URL, l'archivio deve contenere esattamente la
   versione richiesta.
2. Se è presente soltanto la versione, l'add-on usa le credenziali Foundry per
   ottenere l'URL di quella versione.
3. Se è presente soltanto l'URL, la versione viene letta dal `package.json`
   contenuto nell'archivio.
4. Se mancano sia versione sia URL, l'operazione viene rifiutata.
5. Sono accettate soltanto versioni nel formato `14.<build>`; una nuova
   generazione richiede una nuova versione dell'add-on.
6. Se la versione richiesta è già installata, il comando è considerato
   completato senza un nuovo download.

L'URL ha priorità come sorgente; la versione esplicita ha priorità come vincolo
di validazione.

## Flusso transazionale

1. Scaricare in un file temporaneo dentro `/config/container_cache`.
2. Verificare risposta HTTP, tipo ZIP e presenza del `package.json`.
3. Ricavare `generation.build` e confrontarlo con la versione esplicita,
   quando presente.
4. Estrarre in una directory temporanea sullo stesso filesystem di
   `/config/foundry_app`.
5. Verificare nuovamente versione, `resources/app/main.mjs` e struttura
   minima dell'applicazione.
6. Applicare proprietario e gruppo `1000:1000`.
7. Rinominare l'installazione corrente come copia precedente e promuovere
   atomicamente quella nuova.
8. Avviare Foundry con la nuova versione. La precedente resta disponibile per
   il rollback finché il nuovo avvio non è stato confermato.
9. Registrare in `/config` la versione completata. Se l'opzione rimane
   accidentalmente su `true`, i riavvii successivi non ripetono l'operazione.

Qualsiasi errore prima della promozione lascia intatta l'installazione corrente.
Un errore di avvio durante la fase di conferma ripristina la copia precedente.
La cartella `/config/Data` non viene mai spostata né cancellata.

## Approcci considerati

### Versione esplicita

Deterministico e compatibile con il flusso manuale previsto da Foundry. Richiede
che l'utente conosca la build desiderata.

### Versione ricavata dall'URL

Comodo quando il portale Foundry fornisce direttamente un URL temporaneo.
L'archivio deve comunque superare tutte le verifiche e l'URL può scadere.

### Combinazione scelta

Supportare entrambi. Se sono compilati entrambi, l'URL fornisce i byte e la
versione esplicita impedisce di installare per errore un archivio diverso.
La ricerca automatica dell'ultima release è esclusa.

## Vincoli

L'immagine `felddy/foundryvtt` associa ogni release a una specifica versione
del container e avverte quando applicazione e container non coincidono. La
modalità è quindi limitata alla generazione 14 e mostrerà un avviso se la build
obiettivo è più nuova della base. L'aggiornamento dell'add-on resta il metodo
preferito quando è disponibile un'immagine upstream corrispondente.

## Verifica

- Test con archivi ZIP minimi: versione corretta, mismatch, URL senza versione,
  archivio non valido e generazione diversa da 14.
- Test che un errore lasci invariata l'installazione corrente.
- Test di promozione e rollback sullo stesso filesystem.
- Test di idempotenza dopo un aggiornamento riuscito.
- Controllo che `Data`, `Config`, `Backups` e `Logs` non vengano toccati.
- Validazione `bash -n`, YAML e avvio manuale su Home Assistant OS.
