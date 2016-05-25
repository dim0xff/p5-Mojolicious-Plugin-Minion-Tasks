package MyApp::Task::Two::One;

use Mojo::Base -base;

has [qw(app config)];

sub name {'two'}

sub process {
    my ( $self, $job, %args ) = @_;

    $args{cb}->( $self->config );
}

1;

