ruleset gossip_protocol {
    meta {
        name "Gossip Protocol"
        description <<
            A ruleset implementing a gossip protocol for temperature readings
            >>
        author "Jared Huch"
        shares schedule, ownSeenLedger, ownMessageID, getPeer, inNeedOfRumors, peerSubscription
        use module io.picolabs.wrangler alias wrangler
        use module io.picolabs.subscription alias subscription
    }

    global {
        schedule = function(){schedule:list()};

        default_period = 3

        ownSeenLedger = function() {
            ent:seen_ledger{ent:own_id}
        }

        ownMessageID = function() {
            ent:own_id + ent:message_counter.as("String")
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

        highestSequenceFor = function(sensorID) {
            temp = ownSeenLedger(){sensorID} // does this error or is it undefined?
            temp || -1 // if not found, return -1, for which 0 is still the next in the sequence
        }

        allPeers = function() {
            subscription:established().filter(function(subscription) { subscription{"Rx_role"} == "node" });
        }

        arraySum = function(myArray) {
            myArray.reduce(function(lhs,rhs) { lhs + rhs })
        }

        getPeer = function() { // id to dict {id1: 3, id2: 5, id3: 10 }
            ourScore = ownSeenLedger().values().reduce(function(lhs,rhs) {lhs + rhs})
            ownKeys = ownSeenLedger().keys()
            // examine other nodes' ledgers only considering own keys
            seenLedgersWithOnlyOwnKeys = ent:seen_ledger.map(function(v,k) { v.filter(function(val,key) { ownKeys >< key } )})
            // for each node, map of node to the sum of all messages seen by that node from a node we have information on 
            scoredLedgers = seenLedgersWithOnlyOwnKeys.map(function(v,k) { v.values().reduce(function(lhs,rhs) { lhs + rhs })}) // {id1: score, id2: score, id3: score, ...}
            minVal = scoredLedgers.values().sort().head()
            
            // if the minVal is not lower than ourScore, then there are no peers that we can help by sending rumors
            // otherwise, the peer that we can most help if the peer corresponding to the lowest score (farthest behind on rumors)
            peer = minVal < ourScore => scoredLedgers.filter(function(v,k) { v == minVal }).keys().head() | null 
            
            peer
        }

        inNeedOfRumors = function(peerSeenLedger) { // TODO: Return array
            // for a given peer, return those rumors it needs
            1
        }

        peerSubscription = function(peerId) {
            // get the subscription information for the given peer
            1
        }

        prepareMessage = function(peer) {
            // if we have a peer (non-null), send a needed rumor
            // else, send a seen message to all subscribers
            1
        }
    }

    rule init {
        select when wrangler ruleset_installed where event:attrs{"rids"} >< meta:rid
                 or gossip reset 

        pre {
            period = ent:period.defaultsTo(event:attr("period") || default_period)
        }
        
        always {
            ent:own_id := random:uuid()
            ent:message_counter := 0
            ent:seen_ledger := {}.put(ent:own_id, {}) // id to dict {id1: 3, id2: 5, id3: 10 }
            ent:rumor_ledger := {} // {id: [{"MessageID": "asdkf", ...}, ...]}
            schedule gossip event "heartbeat" repeat << */#{period} * * * * * >>  attributes {}
        }
    }

    rule react_to_sensor_reading {
        select when wovyn new_temperature_reading

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
        select when gossip heartbeat 

        pre {
            peerInNeed = getPeer() // SensorId of peer (operation on seen ledger)
            rumors = inNeedOfRumors(ent:seen_ledger{peerInNeed}) // return array
            peerSubscription = peerSubscription(peerInNeed)
        }

        if peerInNeed then noop()

        fired {
            // send needed rumors to peer
            raise gossip event "rumors_to_peer" attributes {"rumors": rumors, "peer": peerSubscription}
        }
        else {
            // send a `seen` event to all peers
            raise gossip event "seen_to_peers"
        }
    }
    
    rule send_rumors_to_peer {
        select when gossip rumors_to_peer foreach event:attrs{"rumors"} setting(rumor)

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
        select when gossip seen_to_peers foreach allPeers() setting(peer)

        pre {
            seenMessage = ownSeenLedger()
            tx = peer{"Tx"}
            rx = peer{"Rx"}
            host = peer{"Tx_host"} || meta:host
        }

        event:send(
            { "eci": tx,
              "eid": "seen_to_peers",
              "domain": "gossip",
              "type": "seen",
              "attrs": {
                "seen": seenMessage,
                "Rx": rx,
                "Host": host
              }
            },
            host=host
        )
    }

    rule rumor_received { 
        select when gossip rumor

        pre {
            rumor = event:attrs{"rumor"}
            sensorID = rumor{"SensorID"}
            sequenceNum = rumor{"MessageID"}.split(re#:#)[1]
            highestSequence = highestSequenceFor(sensorID)
        }

        if sequenceNum == highestSequence + 1 then noop() // if next rumor in sequence

        fired {
            // update seen ledger conditionally
            ent:seen_ledger{sensorID} := ownSeenLedger().put(sensorID, sequenceNum) 
        }
        finally {
            // always record the rumor
            ent:rumor_ledger{sensorID} := ent:rumor_ledger{sensorID}.defaultsTo([]).append(rumor).unique() 
        }
    }

    rule seen_received { // If the seen message is missing info we have, send it
        select when gossip seen 

        pre {
            seenLedger = event:attrs{"seen"}
            tx = event:attrs{"Rx"}
            host = event:attrs{"Host"}
            rumors = inNeedOfRumors(seenLedger)
        }

        if rumors.length() then noop()

        fired {
            raise gossip event "rumors_to_peer" attributes {"rumors": rumors, "peer": {"Tx": tx, "Tx_host": host}} // spoof subscription info
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
}