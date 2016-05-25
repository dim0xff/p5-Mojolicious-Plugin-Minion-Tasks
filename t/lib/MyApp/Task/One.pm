package MyApp::Task::One;

use Mojo::Base -base;

has [qw(app config)];

sub name {'one'}

sub process { }

1;

