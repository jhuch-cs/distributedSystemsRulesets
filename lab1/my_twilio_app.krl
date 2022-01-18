ruleset my_twilio_app {
  meta {
    use module com.twilio.sdk alias sdk
      with
        auth_token = meta:rulesetConfig{"auth_token"}
        sid = meta:rulesetConfig{"sid"}
    //shares sendDefault
  }
  global {
    // sendDefault = function() {
    //   sdk:sendMessage("Hello, World")
    // }
  }
  rule send_message {
    select when message send
    sdk:sendMessage(event:attrs{"msg"}) setting(response)
    fired {
      ent:lastResponse := response
      raise message event "sent" attributes event:attrs
    }
  }
  rule list_messages {
    select when message list
    send_directive(sdk:messages(event:attrs{"page_size"}, event:attrs{"to_number"}, event:attrs{"from_number"}))
    fired {
      raise message event "listed" attributes event:attrs
    }
  }
}