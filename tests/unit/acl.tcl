start_server {tags {"acl external:skip"}} {
    test {Connections start with the default user} {
        r ACL WHOAMI
    } {default}

    test {It is possible to create new users} {
        r ACL setuser newuser
    }

    test {New users start disabled} {
        r ACL setuser newuser >passwd1
        catch {r AUTH newuser passwd1} err
        set err
    } {*WRONGPASS*}

    test {Enabling the user allows the login} {
        r ACL setuser newuser on +acl
        r AUTH newuser passwd1
        r ACL WHOAMI
    } {newuser}

    test {Only the set of correct passwords work} {
        r ACL setuser newuser >passwd2
        catch {r AUTH newuser passwd1} e
        assert {$e eq "OK"}
        catch {r AUTH newuser passwd2} e
        assert {$e eq "OK"}
        catch {r AUTH newuser passwd3} e
        set e
    } {*WRONGPASS*}

    test {It is possible to remove passwords from the set of valid ones} {
        r ACL setuser newuser <passwd1
        catch {r AUTH newuser passwd1} e
        set e
    } {*WRONGPASS*}

    test {Test password hashes can be added} {
        r ACL setuser newuser #34344e4d60c2b6d639b7bd22e18f2b0b91bc34bf0ac5f9952744435093cfb4e6
        catch {r AUTH newuser passwd4} e
        assert {$e eq "OK"}
    }

    test {Test password hashes validate input} {
        # Validate Length
        catch {r ACL setuser newuser #34344e4d60c2b6d639b7bd22e18f2b0b91bc34bf0ac5f9952744435093cfb4e} e
        # Validate character outside set
        catch {r ACL setuser newuser #34344e4d60c2b6d639b7bd22e18f2b0b91bc34bf0ac5f9952744435093cfb4eq} e
        set e
    } {*Error in ACL SETUSER modifier*}

    test {ACL GETUSER returns the password hash instead of the actual password} {
        set passstr [dict get [r ACL getuser newuser] passwords]
        assert_match {*34344e4d60c2b6d639b7bd22e18f2b0b91bc34bf0ac5f9952744435093cfb4e6*} $passstr
        assert_no_match {*passwd4*} $passstr
    }

    test {Test hashed passwords removal} {
        r ACL setuser newuser !34344e4d60c2b6d639b7bd22e18f2b0b91bc34bf0ac5f9952744435093cfb4e6
        set passstr [dict get [r ACL getuser newuser] passwords]
        assert_no_match {*34344e4d60c2b6d639b7bd22e18f2b0b91bc34bf0ac5f9952744435093cfb4e6*} $passstr
    }

    test {By default users are not able to access any command} {
        catch {r SET foo bar} e
        set e
    } {*NOPERM*set*}

    test {By default users are not able to access any key} {
        r ACL setuser newuser +set
        catch {r SET foo bar} e
        set e
    } {*NOPERM*key*}

    test {It's possible to allow the access of a subset of keys} {
        r ACL setuser newuser allcommands ~foo:* ~bar:*
        r SET foo:1 a
        r SET bar:2 b
        catch {r SET zap:3 c} e
        r ACL setuser newuser allkeys; # Undo keys ACL
        set e
    } {*NOPERM*key*}

    test {By default users are able to publish to any channel} {
        r ACL setuser psuser on >pspass +acl +client +@pubsub
        r AUTH psuser pspass
        r PUBLISH foo bar
    } {0}

    test {By default users are able to publish to any shard channel} {
        r SPUBLISH foo bar
    } {0}

    test {By default users are able to subscribe to any channel} {
        set rd [redis_deferring_client]
        $rd AUTH psuser pspass
        $rd read
        $rd SUBSCRIBE foo
        assert_match {subscribe foo 1} [$rd read]
        $rd close
    } {0}

    test {By default users are able to subscribe to any shard channel} {
        set rd [redis_deferring_client]
        $rd AUTH psuser pspass
        $rd read
        $rd SSUBSCRIBE foo
        assert_match {ssubscribe foo 1} [$rd read]
        $rd close
    } {0}

    test {By default users are able to subscribe to any pattern} {
        set rd [redis_deferring_client]
        $rd AUTH psuser pspass
        $rd read
        $rd PSUBSCRIBE bar*
        assert_match {psubscribe bar\* 1} [$rd read]
        $rd close
    } {0}

    test {It's possible to allow publishing to a subset of channels} {
        r ACL setuser psuser resetchannels &foo:1 &bar:*
        assert_equal {0} [r PUBLISH foo:1 somemessage]
        assert_equal {0} [r PUBLISH bar:2 anothermessage]
        catch {r PUBLISH zap:3 nosuchmessage} e
        set e
    } {*NOPERM*channel*}

    test {It's possible to allow publishing to a subset of shard channels} {
        r ACL setuser psuser resetchannels &foo:1 &bar:*
        assert_equal {0} [r SPUBLISH foo:1 somemessage]
        assert_equal {0} [r SPUBLISH bar:2 anothermessage]
        catch {r SPUBLISH zap:3 nosuchmessage} e
        set e
    } {*NOPERM*channel*}

    test {Validate subset of channels is prefixed with resetchannels flag} {
        r ACL setuser hpuser on nopass resetchannels &foo +@all

        # Verify resetchannels flag is prefixed before the channel name(s)
        set users [r ACL LIST]
        set curruser "hpuser"
        foreach user [lshuffle $users] {
            if {[string first $curruser $user] != -1} {
                assert_equal {user hpuser on nopass resetchannels &foo +@all} $user
            }
        }

        # authenticate as hpuser
        r AUTH hpuser pass

        assert_equal {0} [r PUBLISH foo bar]
        catch {r PUBLISH bar game} e

        # Falling back to psuser for the below tests
        r AUTH psuser pspass
        r ACL deluser hpuser
        set e
    } {*NOPERM*channel*}

    test {In transaction queue publish/subscribe/psubscribe to unauthorized channel will fail} {
        r ACL setuser psuser +multi +discard
        r MULTI
        assert_error {*NOPERM*channel*} {r PUBLISH notexits helloworld}
        r DISCARD
        r MULTI
        assert_error {*NOPERM*channel*} {r SUBSCRIBE notexits foo:1}
        r DISCARD
        r MULTI
        assert_error {*NOPERM*channel*} {r PSUBSCRIBE notexits:* bar:*}
        r DISCARD
    }

    test {It's possible to allow subscribing to a subset of channels} {
        set rd [redis_deferring_client]
        $rd AUTH psuser pspass
        $rd read
        $rd SUBSCRIBE foo:1
        assert_match {subscribe foo:1 1} [$rd read]
        $rd SUBSCRIBE bar:2
        assert_match {subscribe bar:2 2} [$rd read]
        $rd SUBSCRIBE zap:3
        catch {$rd read} e
        set e
    } {*NOPERM*channel*}

    test {It's possible to allow subscribing to a subset of shard channels} {
        set rd [redis_deferring_client]
        $rd AUTH psuser pspass
        $rd read
        $rd SSUBSCRIBE foo:1
        assert_match {ssubscribe foo:1 1} [$rd read]
        $rd SSUBSCRIBE bar:2
        assert_match {ssubscribe bar:2 2} [$rd read]
        $rd SSUBSCRIBE zap:3
        catch {$rd read} e
        set e
    } {*NOPERM*channel*}

    test {It's possible to allow subscribing to a subset of channel patterns} {
        set rd [redis_deferring_client]
        $rd AUTH psuser pspass
        $rd read
        $rd PSUBSCRIBE foo:1
        assert_match {psubscribe foo:1 1} [$rd read]
        $rd PSUBSCRIBE bar:*
        assert_match {psubscribe bar:\* 2} [$rd read]
        $rd PSUBSCRIBE bar:baz
        catch {$rd read} e
        set e
    } {*NOPERM*channel*}
    
    test {Subscribers are killed when revoked of channel permission} {
        set rd [redis_deferring_client]
        r ACL setuser psuser resetchannels &foo:1
        $rd AUTH psuser pspass
        $rd read
        $rd CLIENT SETNAME deathrow
        $rd read
        $rd SUBSCRIBE foo:1
        $rd read
        r ACL setuser psuser resetchannels
        assert_no_match {*deathrow*} [r CLIENT LIST]
        $rd close
    } {0}

    test {Subscribers are killed when revoked of channel permission} {
        set rd [redis_deferring_client]
        r ACL setuser psuser resetchannels &foo:1
        $rd AUTH psuser pspass
        $rd read
        $rd CLIENT SETNAME deathrow
        $rd read
        $rd SSUBSCRIBE foo:1
        $rd read
        r ACL setuser psuser resetchannels
        assert_no_match {*deathrow*} [r CLIENT LIST]
        $rd close
    } {0}

    test {Subscribers are killed when revoked of pattern permission} {
        set rd [redis_deferring_client]
        r ACL setuser psuser resetchannels &bar:*
        $rd AUTH psuser pspass
        $rd read
        $rd CLIENT SETNAME deathrow
        $rd read
        $rd PSUBSCRIBE bar:*
        $rd read
        r ACL setuser psuser resetchannels
        assert_no_match {*deathrow*} [r CLIENT LIST]
        $rd close
    } {0}

    test {Subscribers are pardoned if literal permissions are retained and/or gaining allchannels} {
        set rd [redis_deferring_client]
        r ACL setuser psuser resetchannels &foo:1 &bar:* &orders
        $rd AUTH psuser pspass
        $rd read
        $rd CLIENT SETNAME pardoned
        $rd read
        $rd SUBSCRIBE foo:1
        $rd read
        $rd SSUBSCRIBE orders
        $rd read
        $rd PSUBSCRIBE bar:*
        $rd read
        r ACL setuser psuser resetchannels &foo:1 &bar:* &orders &baz:qaz &zoo:*
        assert_match {*pardoned*} [r CLIENT LIST]
        r ACL setuser psuser allchannels
        assert_match {*pardoned*} [r CLIENT LIST]
        $rd close
    } {0}

    test {Users can be configured to authenticate with any password} {
        r ACL setuser newuser nopass
        r AUTH newuser zipzapblabla
    } {OK}

    test {ACLs can exclude single commands} {
        r ACL setuser newuser -ping
        r INCR mycounter ; # Should not raise an error
        catch {r PING} e
        set e
    } {*NOPERM*ping*}

    test {ACLs can include or exclude whole classes of commands} {
        r ACL setuser newuser -@all +@set +acl
        r SADD myset a b c; # Should not raise an error
        r ACL setuser newuser +@all -@string
        r SADD myset a b c; # Again should not raise an error
        # String commands instead should raise an error
        catch {r SET foo bar} e
        r ACL setuser newuser allcommands; # Undo commands ACL
        set e
    } {*NOPERM*set*}

    test {ACLs can include single subcommands} {
        r ACL setuser newuser +@all -client
        r ACL setuser newuser +client|id +client|setname
        set cmdstr [dict get [r ACL getuser newuser] commands]
        assert_match {+@all*-client*+client|id*} $cmdstr
        assert_match {+@all*-client*+client|setname*} $cmdstr
        r CLIENT ID; # Should not fail
        r CLIENT SETNAME foo ; # Should not fail
        catch {r CLIENT KILL type master} e
        set e
    } {*NOPERM*client|kill*}

    test {ACLs can exclude single subcommands, case 1} {
        r ACL setuser newuser +@all -client|kill
        set cmdstr [dict get [r ACL getuser newuser] commands]
        assert_equal {+@all -client|kill} $cmdstr
        r CLIENT ID; # Should not fail
        r CLIENT SETNAME foo ; # Should not fail
        catch {r CLIENT KILL type master} e
        set e
    } {*NOPERM*client|kill*}

    test {ACLs can exclude single subcommands, case 2} {
        r ACL setuser newuser -@all +acl +config -config|set
        set cmdstr [dict get [r ACL getuser newuser] commands]
        assert_match {*+config*} $cmdstr
        assert_match {*-config|set*} $cmdstr
        r CONFIG GET loglevel; # Should not fail
        catch {r CONFIG SET loglevel debug} e
        set e
    } {*NOPERM*config|set*}

    test {ACLs can include a subcommand with a specific arg} {
        r ACL setuser newuser +@all -config|get
        r ACL setuser newuser +config|get|appendonly
        set cmdstr [dict get [r ACL getuser newuser] commands]
        assert_match {*-config|get*} $cmdstr
        assert_match {*+config|get|appendonly*} $cmdstr
        r CONFIG GET appendonly; # Should not fail
        catch {r CONFIG GET loglevel} e
        set e
    } {*NOPERM*config|get*}

    test {ACLs including of a type includes also subcommands} {
        r ACL setuser newuser -@all +acl +@stream
        r XADD key * field value
        r XINFO STREAM key
    }

    test {ACLs can block SELECT of all but a specific DB} {
        r ACL setuser newuser -@all +acl +select|0
        set cmdstr [dict get [r ACL getuser newuser] commands]
        assert_match {*+select|0*} $cmdstr
        r SELECT 0
        catch {r SELECT 1} e
        set e
    } {*NOPERM*select*}

    test {ACLs can block all DEBUG subcommands except one} {
        r ACL setuser newuser -@all +acl +incr +debug|object
        set cmdstr [dict get [r ACL getuser newuser] commands]
        assert_match {*+debug|object*} $cmdstr
        r INCR key
        r DEBUG OBJECT key
        catch {r DEBUG SEGFAULT} e
        set e
    } {*NOPERM*debug*}

    test {ACLs set can include subcommands, if already full command exists} {
        r ACL setuser bob +memory|doctor
        set cmdstr [dict get [r ACL getuser bob] commands]
        assert_equal {-@all +memory|doctor} $cmdstr

        # Validate the commands have got engulfed to +memory.
        r ACL setuser bob +memory
        set cmdstr [dict get [r ACL getuser bob] commands]
        assert_equal {-@all +memory} $cmdstr

        # Appending to the existing access string of bob.
        r ACL setuser bob +@all +client|id
        # Validate the new commands has got engulfed to +@all.
        set cmdstr [dict get [r ACL getuser bob] commands]
        assert_equal {+@all} $cmdstr

        r ACL setuser bob >passwd1 on
        r AUTH bob passwd1
        r CLIENT ID; # Should not fail
        r MEMORY DOCTOR; # Should not fail
    }

    test {ACLs set can exclude subcommands, if already full command exists} {
        r ACL setuser alice +@all -memory|doctor
        set cmdstr [dict get [r ACL getuser alice] commands]
        assert_equal {+@all -memory|doctor} $cmdstr

        r ACL setuser alice >passwd1 on
        r AUTH alice passwd1

        assert_error {*NOPERM*memory|doctor*} {r MEMORY DOCTOR}
        r MEMORY STATS ;# should work

        # Validate the commands have got engulfed to -memory.
        r ACL setuser alice +@all -memory
        set cmdstr [dict get [r ACL getuser alice] commands]
        assert_equal {+@all -memory} $cmdstr

        assert_error {*NOPERM*memory|doctor*} {r MEMORY DOCTOR}
        assert_error {*NOPERM*memory|stats*} {r MEMORY STATS}

        # Appending to the existing access string of alice.
        r ACL setuser alice -@all

        # Now, alice can't do anything, we need to auth newuser to execute ACL GETUSER
        r AUTH newuser passwd1

        # Validate the new commands has got engulfed to -@all.
        set cmdstr [dict get [r ACL getuser alice] commands]
        assert_equal {-@all} $cmdstr

        r AUTH alice passwd1

        assert_error {*NOPERM*get*} {r GET key}
        assert_error {*NOPERM*memory|stats*} {r MEMORY STATS}

        # Auth newuser before the next test
        r AUTH newuser passwd1
    }

    # Note that the order of the generated ACL rules is not stable in Redis
    # so we need to match the different parts and not as a whole string.
    test {ACL GETUSER is able to translate back command permissions} {
        # Subtractive
        r ACL setuser newuser reset +@all ~* -@string +incr -debug +debug|digest
        set cmdstr [dict get [r ACL getuser newuser] commands]
        assert_match {*+@all*} $cmdstr
        assert_match {*-@string*} $cmdstr
        assert_match {*+incr*} $cmdstr
        assert_match {*-debug +debug|digest**} $cmdstr

        # Additive
        r ACL setuser newuser reset +@string -incr +acl +debug|digest +debug|segfault
        set cmdstr [dict get [r ACL getuser newuser] commands]
        assert_match {*-@all*} $cmdstr
        assert_match {*+@string*} $cmdstr
        assert_match {*-incr*} $cmdstr
        assert_match {*+debug|digest*} $cmdstr
        assert_match {*+debug|segfault*} $cmdstr
        assert_match {*+acl*} $cmdstr
    }

    # A regression test make sure that as long as there is a simple
    # category defining the commands, that it will be used as is.
    test {ACL GETUSER provides reasonable results} {
        set categories [r ACL CAT]

        # Test that adding each single category will
        # result in just that category with both +@all and -@all
        foreach category $categories {
            # Test for future commands where allowed
            r ACL setuser additive reset +@all "-@$category"
            set cmdstr [dict get [r ACL getuser additive] commands]
            assert_equal "+@all -@$category" $cmdstr

            # Test for future commands where disallowed
            r ACL setuser restrictive reset -@all "+@$category"
            set cmdstr [dict get [r ACL getuser restrictive] commands]
            assert_equal "-@all +@$category" $cmdstr
        }
    }

    test {ACL #5998 regression: memory leaks adding / removing subcommands} {
        r AUTH default ""
        r ACL setuser newuser reset -debug +debug|a +debug|b +debug|c
        r ACL setuser newuser -debug
        # The test framework will detect a leak if any.
    }

    test {ACL LOG shows failed command executions at toplevel} {
        r ACL LOG RESET
        r ACL setuser antirez >foo on +set ~object:1234
        r ACL setuser antirez +eval +multi +exec
        r ACL setuser antirez resetchannels +publish
        r AUTH antirez foo
        assert_error "*NOPERM*get*" {r GET foo}
        r AUTH default ""
        set entry [lindex [r ACL LOG] 0]
        assert {[dict get $entry username] eq {antirez}}
        assert {[dict get $entry context] eq {toplevel}}
        assert {[dict get $entry reason] eq {command}}
        assert {[dict get $entry object] eq {get}}
    }

    test "ACL LOG shows failed subcommand executions at toplevel" {
        r ACL LOG RESET
        r ACL DELUSER demo
        r ACL SETUSER demo on nopass
        r AUTH demo ""
        assert_error "*NOPERM*script|help*" {r SCRIPT HELP}
        r AUTH default ""
        set entry [lindex [r ACL LOG] 0]
        assert_equal [dict get $entry username] {demo}
        assert_equal [dict get $entry context] {toplevel}
        assert_equal [dict get $entry reason] {command}
        assert_equal [dict get $entry object] {script|help}
    }

    test {ACL LOG is able to test similar events} {
        r ACL LOG RESET
        r AUTH antirez foo
        catch {r GET foo}
        catch {r GET foo}
        catch {r GET foo}
        r AUTH default ""
        set entry [lindex [r ACL LOG] 0]
        assert {[dict get $entry count] == 3}
    }

    test {ACL LOG is able to log keys access violations and key name} {
        r AUTH antirez foo
        catch {r SET somekeynotallowed 1234}
        r AUTH default ""
        set entry [lindex [r ACL LOG] 0]
        assert {[dict get $entry reason] eq {key}}
        assert {[dict get $entry object] eq {somekeynotallowed}}
    }

    test {ACL LOG is able to log channel access violations and channel name} {
        r AUTH antirez foo
        catch {r PUBLISH somechannelnotallowed nullmsg}
        r AUTH default ""
        set entry [lindex [r ACL LOG] 0]
        assert {[dict get $entry reason] eq {channel}}
        assert {[dict get $entry object] eq {somechannelnotallowed}}
    }

    test {ACL LOG RESET is able to flush the entries in the log} {
        r ACL LOG RESET
        assert {[llength [r ACL LOG]] == 0}
    }

    test {ACL LOG can distinguish the transaction context (1)} {
        r AUTH antirez foo
        r MULTI
        catch {r INCR foo}
        catch {r EXEC}
        r AUTH default ""
        set entry [lindex [r ACL LOG] 0]
        assert {[dict get $entry context] eq {multi}}
        assert {[dict get $entry object] eq {incr}}
    }

    test {ACL LOG can distinguish the transaction context (2)} {
        set rd1 [redis_deferring_client]
        r ACL SETUSER antirez +incr

        r AUTH antirez foo
        r MULTI
        r INCR object:1234
        $rd1 ACL SETUSER antirez -incr
        $rd1 read
        catch {r EXEC}
        $rd1 close
        r AUTH default ""
        set entry [lindex [r ACL LOG] 0]
        assert {[dict get $entry context] eq {multi}}
        assert {[dict get $entry object] eq {incr}}
        r ACL SETUSER antirez -incr
    }

    test {ACL can log errors in the context of Lua scripting} {
        r AUTH antirez foo
        catch {r EVAL {redis.call('incr','foo')} 0}
        r AUTH default ""
        set entry [lindex [r ACL LOG] 0]
        assert {[dict get $entry context] eq {lua}}
        assert {[dict get $entry object] eq {incr}}
    }

    test {ACL LOG can accept a numerical argument to show less entries} {
        r AUTH antirez foo
        catch {r INCR foo}
        catch {r INCR foo}
        catch {r INCR foo}
        catch {r INCR foo}
        r AUTH default ""
        assert {[llength [r ACL LOG]] > 1}
        assert {[llength [r ACL LOG 2]] == 2}
    }

    test {ACL LOG can log failed auth attempts} {
        catch {r AUTH antirez wrong-password}
        set entry [lindex [r ACL LOG] 0]
        assert {[dict get $entry context] eq {toplevel}}
        assert {[dict get $entry reason] eq {auth}}
        assert {[dict get $entry object] eq {AUTH}}
        assert {[dict get $entry username] eq {antirez}}
    }

    test {ACL LOG entries are limited to a maximum amount} {
        r ACL LOG RESET
        r CONFIG SET acllog-max-len 5
        r AUTH antirez foo
        for {set j 0} {$j < 10} {incr j} {
            catch {r SET obj:$j 123}
        }
        r AUTH default ""
        assert {[llength [r ACL LOG]] == 5}
    }

    test {When default user is off, new connections are not authenticated} {
        r ACL setuser default off
        catch {set rd1 [redis_deferring_client]} e
        r ACL setuser default on
        set e
    } {*NOAUTH*}

    test {When default user has no command permission, hello command still works for other users} {
        r ACL setuser secure-user >supass on +@all
        r ACL setuser default -@all
        r HELLO 2 AUTH secure-user supass
        r ACL setuser default nopass +@all
        r AUTH default ""
    }

    test {ACL HELP should not have unexpected options} {
        catch {r ACL help xxx} e
        assert_match "*wrong number of arguments*" $e
    }

    test {Delete a user that the client doesn't use} {
        r ACL setuser not_used on >passwd
        assert {[r ACL deluser not_used] == 1}
        # The client is not closed
        assert {[r ping] eq {PONG}}
    }

    test {Delete a user that the client is using} {
        r ACL setuser using on +acl >passwd
        r AUTH using passwd
        # The client will receive reply normally
        assert {[r ACL deluser using] == 1}
        # The client is closed
        catch {[r ping]} e
        assert_match "*I/O error*" $e
    }
}

set server_path [tmpdir "server.acl"]
exec cp -f tests/assets/user.acl $server_path
start_server [list overrides [list "dir" $server_path "aclfile" "user.acl"] tags [list "external:skip"]] {
    # user alice on allcommands allkeys >alice
    # user bob on -@all +@set +acl ~set* >bob
    # user default on nopass ~* +@all

    test {default: load from include file, can access any channels} {
        r SUBSCRIBE foo
        r PSUBSCRIBE bar*
        r UNSUBSCRIBE
        r PUNSUBSCRIBE
        r PUBLISH hello world
    }

    test {default: with config acl-pubsub-default allchannels after reset, can access any channels} {
        r ACL setuser default reset on nopass ~* +@all
        r SUBSCRIBE foo
        r PSUBSCRIBE bar*
        r UNSUBSCRIBE
        r PUNSUBSCRIBE
        r PUBLISH hello world
    }

    test {default: with config acl-pubsub-default resetchannels after reset, can not access any channels} {
        r CONFIG SET acl-pubsub-default resetchannels
        r ACL setuser default reset on nopass ~* +@all
        assert_error {*NOPERM*channel*} {r SUBSCRIBE foo}
        assert_error {*NOPERM*channel*} {r PSUBSCRIBE bar*}
        assert_error {*NOPERM*channel*} {r PUBLISH hello world}
        r CONFIG SET acl-pubsub-default resetchannels
    }

    test {Alice: can execute all command} {
        r AUTH alice alice
        assert_equal "alice" [r acl whoami]
        r SET key value
    }

    test {Bob: just execute @set and acl command} {
        r AUTH bob bob
        assert_equal "bob" [r acl whoami]
        assert_equal "3" [r sadd set 1 2 3]
        catch {r SET key value} e
        set e
    } {*NOPERM*set*}

    test {ACL load and save} {
        r ACL setuser eve +get allkeys >eve on
        r ACL save

        # ACL load will free user and kill clients
        r ACL load
        catch {r ACL LIST} e
        assert_match {*I/O error*} $e

        reconnect
        r AUTH alice alice
        r SET key value
        r AUTH eve eve
        r GET key
        catch {r SET key value} e
        set e
    } {*NOPERM*set*}

    test {ACL load and save with restricted channels} {
        r AUTH alice alice
        r ACL setuser harry on nopass resetchannels &test +@all ~*
        r ACL save

        # ACL load will free user and kill clients
        r ACL load
        catch {r ACL LIST} e
        assert_match {*I/O error*} $e

        reconnect
        r AUTH harry anything
        r publish test bar
        catch {r publish test1 bar} e
        r ACL deluser harry
        set e
    } {*NOPERM*channel*}
}

set server_path [tmpdir "resetchannels.acl"]
exec cp -f tests/assets/nodefaultuser.acl $server_path
exec cp -f tests/assets/default.conf $server_path
start_server [list overrides [list "dir" $server_path "acl-pubsub-default" "resetchannels" "aclfile" "nodefaultuser.acl"] tags [list "external:skip"]] {

    test {Default user has access to all channels irrespective of flag} {
        set channelinfo [dict get [r ACL getuser default] channels]
        assert_equal "&*" $channelinfo
        set channelinfo [dict get [r ACL getuser alice] channels]
        assert_equal "" $channelinfo
    }

    test {Update acl-pubsub-default, existing users shouldn't get affected} {
        set channelinfo [dict get [r ACL getuser default] channels]
        assert_equal "&*" $channelinfo
        r CONFIG set acl-pubsub-default allchannels
        r ACL setuser mydefault
        set channelinfo [dict get [r ACL getuser mydefault] channels]
        assert_equal "&*" $channelinfo
        r CONFIG set acl-pubsub-default resetchannels
        set channelinfo [dict get [r ACL getuser mydefault] channels]
        assert_equal "&*" $channelinfo
    }

    test {Single channel is valid} {
        r ACL setuser onechannel &test
        set channelinfo [dict get [r ACL getuser onechannel] channels]
        assert_equal "&test" $channelinfo
        r ACL deluser onechannel
    }

    test {Single channel is not valid with allchannels} {
        r CONFIG set acl-pubsub-default allchannels
        catch {r ACL setuser onechannel &test} err
        r CONFIG set acl-pubsub-default resetchannels
        set err
    } {*start with an empty list of channels*}
}

set server_path [tmpdir "resetchannels.acl"]
exec cp -f tests/assets/nodefaultuser.acl $server_path
exec cp -f tests/assets/default.conf $server_path
start_server [list overrides [list "dir" $server_path "acl-pubsub-default" "resetchannels" "aclfile" "nodefaultuser.acl"] tags [list "external:skip"]] {

    test {Only default user has access to all channels irrespective of flag} {
        set channelinfo [dict get [r ACL getuser default] channels]
        assert_equal "&*" $channelinfo
        set channelinfo [dict get [r ACL getuser alice] channels]
        assert_equal "" $channelinfo
    }
}


start_server {overrides {user "default on nopass ~* +@all"} tags {"external:skip"}} {
    test {default: load from config file, can access any channels} {
        r SUBSCRIBE foo
        r PSUBSCRIBE bar*
        r UNSUBSCRIBE
        r PUNSUBSCRIBE
        r PUBLISH hello world
    }
}

set server_path [tmpdir "duplicate.acl"]
exec cp -f tests/assets/user.acl $server_path
exec cp -f tests/assets/default.conf $server_path
start_server [list overrides [list "dir" $server_path "aclfile" "user.acl"] tags [list "external:skip"]] {

    test {Test loading an ACL file with duplicate users} {
        exec cp -f tests/assets/user.acl $server_path

        # Corrupt the ACL file
        set corruption "\nuser alice on nopass ~* -@all"
        exec echo $corruption >> $server_path/user.acl
        catch {r ACL LOAD} err
        assert_match {*Duplicate user 'alice' found*} $err 

        # Verify the previous users still exist
        # NOTE: A missing user evaluates to an empty
        # string. 
        assert {[r ACL GETUSER alice] != ""}
        assert_equal [dict get [r ACL GETUSER alice] commands] "+@all"
        assert {[r ACL GETUSER bob] != ""}
        assert {[r ACL GETUSER default] != ""}
    }

    test {Test loading an ACL file with duplicate default user} {
        exec cp -f tests/assets/user.acl $server_path

        # Corrupt the ACL file
        set corruption "\nuser default on nopass ~* -@all"
        exec echo $corruption >> $server_path/user.acl
        catch {r ACL LOAD} err
        assert_match {*Duplicate user 'default' found*} $err 

        # Verify the previous users still exist
        # NOTE: A missing user evaluates to an empty
        # string. 
        assert {[r ACL GETUSER alice] != ""}
        assert_equal [dict get [r ACL GETUSER alice] commands] "+@all"
        assert {[r ACL GETUSER bob] != ""}
        assert {[r ACL GETUSER default] != ""}
    }
    
    test {Test loading duplicate users in config on startup} {
        catch {exec src/redis-server --user foo --user foo} err
        assert_match {*Duplicate user*} $err

        catch {exec src/redis-server --user default --user default} err
        assert_match {*Duplicate user*} $err
    } {} {external:skip}
}
