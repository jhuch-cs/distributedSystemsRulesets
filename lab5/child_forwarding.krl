ruleset child_forwarding {
    meta {
        use module io.picolabs.wrangler alias wrangler
        shares requestQueryForwarding
    }

    global {
        requestQueryForwarding = function(child_eci, ruleset_rid, func_name) {
            wrangler:picoQuery(child_eci, ruleset_rid, func_name)
        }
    }



    rule forward_to_child {
        select when sensor request_event_forwarding
        
        pre {
            child_eci = event:attrs{"eci"}
            event_domain = event:attrs{"domain"}
            event_type = event:attrs{"type"}
        }

        event:send(
            { "eci": child_eci,
              "eid": "forward-query",
              "domain": event_domain,
              "type": event_type,
            }
        )
    }
}