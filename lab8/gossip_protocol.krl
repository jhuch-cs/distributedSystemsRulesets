ruleset gossip_protocol {
    meta {
        name "Gossip Protocol"
        description <<
            A ruleset implementing a gossip protocol for temperature readings
            >>
        author "Jared Huch"
        shares schedule, ownSeenLedger, ownMessageID, getPeer, inNeedOfRumors, peerSubscription, seenLedger, rumorLedger, ids_to_subs, highestSequenceAfterFillingHole
        use module io.picolabs.wrangler alias wrangler
        use module io.picolabs.subscription alias subscription
    }

    global {
        schedule = function(){schedule:list()};

        default_period = 3

        seenLedger = function() { // DELETEME: Testing only
            ent:seen_ledger
        }

        rumorLedger = function() { // DELETEME: Testing only
            ent:rumor_ledger
        }

        ids_to_subs = function() { // DELETEME: Testing only
            ent:ids_to_subs
        }

        ownSeenLedger = function() {
            ent:seen_ledger{ent:own_id}
        }

        ownMessageID = function() {
            ent:own_id + ":" + ent:message_counter.as("String")
        }

        createOwnRumor = function(temp, time) {
            {"MessageID": ownMessageID(),
             "SensorID": ent:own_id,
             "Temperature": temp,
             "Timestamp": time
            }
        }

        unseen = function(rumor) {
            sensorID = rumor{"SensorID"}
            ent:rumor_ledger{sensorID} >< rumor
        }

        picoOn = function() {
            ent:is_on
        }

        sequenceNumFromMessageID = function(messageID) {
            messageID.split(re#:#)[1].as("Number")
        }

        highestRecordedSequence = function(sensorID) { // this method is a little too dumb
            temp = ownSeenLedger(){sensorID}
            temp.isnull() => -1 | temp // if not found, return -1, for which 0 is still the next in the sequence
        }

        highestSequenceAfterFillingHole = function(sensorID) { // manually compute the highest sequence
            recordedRumors = ent:rumor_ledger{sensorID} || []
            rumorSequenceNums = recordedRumors.map(function(rumor) { sequenceNumFromMessageID(rumor{"MessageID"}) })
            sortedSequence = rumorSequenceNums.sort("numeric")
            // get highest val in sequence, starting with -1 in order to include 0
            highestInSequence = sortedSequence.reduce(function(accum, curr) { curr == accum + 1 => curr | accum }, -1) 
            highestInSequence
        }

        allPeers = function() {
            subscription:established().filter(function(subscription) { subscription{"Rx_role"} == "node" });
        }

        getPeer = function() { // id to dict {id1: 3, id2: 5, id3: 10 }
            ourScore = ownSeenLedger().values().reduce(function(lhs,rhs) {lhs + rhs})
            ownKeys = ownSeenLedger().keys()
            // examine other nodes' ledgers only considering own keys
            seenLedgersWithOnlyOwnKeys = ent:seen_ledger.map(function(v,k) { v.filter(function(val,key) { ownKeys >< key } )})
            // for each node, map of node to the sum of all messages seen by that node from a node we have information on (plus one to count 0 as part of sequence)
            scoredLedgers = seenLedgersWithOnlyOwnKeys.map(function(v,k) { v.values().reduce(function(lhs,rhs) { lhs + rhs + 1 })}) // {id1: score, id2: score, id3: score, ...}
            minVal = scoredLedgers.values().sort("numeric").head()
            
            // if the minVal is not lower than ourScore, then there are no peers that we can help by sending rumors
            // otherwise, the peer that we can most help if the peer corresponding to the lowest score (farthest behind on rumors)
            peerOrSelf = minVal < ourScore => scoredLedgers.filter(function(v,k) { v == minVal }).keys().head() | null 

            peer = peerOrSelf == ent:own_id => null | peerOrSelf // don't return own node
            
            peer
        }

        inNeedOfRumors = function(peerSeenLedger) {
            // for a given peer, return those rumors it needs
            ownKeys = ownSeenLedger().keys()
            seenLedgerOnlyOwnKeys = peerSeenLedger.filter(function(val,key) { ownKeys >< key } )

            neededRumorsMap = ent:rumor_ledger.map(function(v,k) { 
                v.filter(function(rumor) { 
                    rumorSequence = sequenceNumFromMessageID(rumor{"MessageID"})
                    ledgerSequence = seenLedgerOnlyOwnKeys{k}.isnull() => -1 | seenLedgerOnlyOwnKeys{k} 
                    rumorSequence > ledgerSequence })}) // k is sensorID, v is array of rumors
            neededRumors = neededRumorsMap.values().reduce(function(lhs, rhs) { lhs.append(rhs) }) // flatten

            neededRumors.klog("neededRumors*")
        }

        peerSubscription = function(peerId) {
            tx = ent:ids_to_subs{peerId}.klog("Tx in peerSubscription")
            allPeers().klog("All peers").filter(function(peer) { peer{"Tx"} == tx }).head()
        }
    }

    rule init {
        select when wrangler ruleset_installed where event:attrs{"rids"} >< meta:rid
                 or gossip reset 

        pre {
            period = ent:period.defaultsTo(event:attrs{"period"} || default_period)
            scheduled_event = schedule:list().reverse().head() // unsafe if we ever schedule other repeat events in this ruleset
            id = scheduled_event{"id"}
        }

        if id then schedule:remove(id)
        
        always {
            ent:own_id := random:uuid()
            ent:message_counter := 0
            ent:seen_ledger := {}.put(ent:own_id, {}) // id to dict {id1: 3, id2: 5, id3: 10 }
            ent:rumor_ledger := {} // {id: [{"MessageID": "asdkf", ...}, ...]}
            ent:ids_to_subs := {}
            ent:is_on := true
            schedule gossip event "heartbeat" repeat << */#{period} * * * * * >>  attributes {}
        }
    }

    rule react_to_sensor_reading {
        select when wovyn new_temperature_reading where picoOn()

        pre {
            temp = event:attrs{"temperature"}
            time = event:attrs{"timestamp"}
            rumor = createOwnRumor(temp, time)
        }

        always {
            raise gossip event "rumor" attributes {"rumor": rumor}
            ent:message_counter := ent:message_counter + 1
        }
    }

    rule react_to_heartbeat {
        select when gossip heartbeat where picoOn()

        pre {
            peerInNeed = getPeer() 
            peerLedger = ent:seen_ledger{peerInNeed} || {}
            rumors = inNeedOfRumors(peerLedger) || []
            peer = peerSubscription(peerInNeed) || null
        }

        if peerInNeed && random:integer(1) then noop() // When we have a peerInNeed, 50% chance of rumor, 50% chance of seen. Otherwise, seen. 

        fired {
            // send needed rumors to peer
            raise gossip event "recompute_sequence" attributes {"SensorID": peerInNeed}
            raise gossip event "rumors_to_peer" attributes {"rumors": rumors, "peer": peer}
        }
        else {
            // send a `seen` event to all peers
            raise gossip event "seen_to_peers"
        }
    }
    
    rule send_rumors_to_peer {
        select when gossip rumors_to_peer where picoOn()
            foreach event:attrs{"rumors"} setting(rumor)

        pre {
            peer = event:attrs{"peer"}
            tx = peer{"Tx"}
            host = peer{"Tx_host"} || meta:host
        }

        event:send(
            { "eci": tx,
              "eid": "rumors_to_peer",
              "domain": "gossip",
              "type": "rumor",
              "attrs": {
                "rumor": rumor,
              }
            },
            host=host
        )
    }

    rule send_seen_to_peers {
        select when gossip seen_to_peers where picoOn()
            foreach allPeers() setting(peer)

        pre {
            seenMessage = ownSeenLedger()
            tx = peer{"Tx"}
            rx = peer{"Rx"}
            host = peer{"Tx_host"} || meta:host
        }

        event:send( // every seen event should give the opportunity to report peers' SensorID and Tx
            { "eci": tx,
              "eid": "seen_to_peers",
              "domain": "gossip",
              "type": "seen",
              "attrs": {
                "seen": seenMessage,
                "Rx": rx,
                "SensorID": ent:own_id,
                "Host": host
              }
            },
            host=host
        )
    }

    rule rumor_received { 
        select when gossip rumor where picoOn()

        pre {
            rumor = event:attrs{"rumor"}
            sensorID = rumor{"SensorID"}
            sequenceNum = sequenceNumFromMessageID(rumor{"MessageID"})
            highestSequence = highestRecordedSequence(sensorID)
        }

        if sequenceNum == highestSequence + 1 then noop() // if next rumor in sequence

        fired {
            // update seen ledger conditionally
            ent:seen_ledger{[ent:own_id, sensorID]} := sequenceNum 
            // adding a new val to the sequence might have filled a previous hole, so re-compute highest in sequence
            raise gossip event "recompute_sequence" attributes {"SensorID": sensorID}
            ent:seen_ledger{[ent:own_id, sensorID]} := highestSequenceAfterFillingHole(sensorID)
        }
        finally {
            // always record the rumor
            ent:rumor_ledger{sensorID} := ent:rumor_ledger{sensorID}.defaultsTo([]).append(rumor).unique() 
            // FIXME: always assume that both creator and sender (possibly the same picos) have also seen this message?
            //        or leave them in charge of their own seen_ledgers and just have them communicate later?
        }
    }

    rule seen_received { // If the seen message is missing info we have, send it
        select when gossip seen where picoOn()

        pre {
            seenLedgerMsg = event:attrs{"seen"}
            tx = event:attrs{"Rx"}.klog("Tx")
            SensorID = event:attrs{"SensorID"}
            host = event:attrs{"Host"}
            rumors = inNeedOfRumors(seenLedgerMsg) || []
        }

        if rumors.length() then noop()

        fired {
            raise gossip event "rumors_to_peer" attributes {"rumors": rumors, "peer": {"Tx": tx, "Tx_host": host}} // spoof subscription info
        }
        finally {
            ent:ids_to_subs{SensorID} := tx // keep record of each peer that has sent us a `seen` message
            ent:seen_ledger{SensorID} := seenLedgerMsg
        }
    }

    rule fill_sequence_hole {
        select when gossip recompute_sequence where picoOn()

        pre {
            sensorID = event:attrs{"SensorID"}
            newSequenceNum = highestSequenceAfterFillingHole(sensorID)
        }

        if newSequenceNum != -1 then noop()

        fired {
            ent:seen_ledger{[ent:own_id, sensorID]} := newSequenceNum
        }
    }

    rule update_period {
        select when gossip update_period
        
        pre {
            period = event:attrs{"period"} || default_period
            scheduled_event = schedule:list().reverse().head() // unsafe if we ever schedule other repeat events in this ruleset
            id = scheduled_event{"id"}
        }

        schedule:remove(id)  

        always {
            schedule gossip event "heartbeat" repeat << */#{period} * * * * * >>  attributes {}
        }
    }

    rule control_messaging {
        select when gossip process

        pre {
            isOn = event:attrs{"status"}.lc() == "on"
        }

        always {
            ent:is_on := isOn
        }
    }
}