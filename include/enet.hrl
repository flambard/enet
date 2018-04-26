%%
%% Send Reliable Command
%%

-record(reliable,
        {
          data = <<>>
        }).


%%
%% Send Unreliable Command
%%

-record(unreliable,
        {
          sequence_number = 0,
          data            = <<>>
        }).


%%
%% Send Unsequenced Command
%%

-record(unsequenced,
        {
          group = 0,
          data  = <<>>
        }).
