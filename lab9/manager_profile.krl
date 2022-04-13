ruleset manager_profile {
    meta {
        name "Manager Profile"
        description <<
            A ruleset to represent the profile of a pico that manages various sensors
            >>
        author "Jared Huch"
        use module com.twilio.sdk alias twilio
            with
                auth_token = meta:rulesetConfig{"auth_token"}
                sid = meta:rulesetConfig{"sid"}
    }

    global {
        sms_number = "+18474602997"
    }

    rule send_threshold_violation_message {
        select when sensor threshold_violation 

        pre {
            temp = event:attrs{"temperature"}
            threshold = event:attrs{"temperature_threshold"}
            message = <<Temperature of #{temp} exceeds threshold of #{threshold}>>
        }

        // twilio:sendMessage(message, sms_number) Don't spam me, please
    }
}