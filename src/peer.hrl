-record(peer,
        { id
        , pid
        , remote_id
        , ip
        , port
        , incoming_session_id = 0
        , outgoing_session_id = 0
        }).
