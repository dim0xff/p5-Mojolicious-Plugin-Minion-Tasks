package MyApp::Task::One::Two;

use Mojo::Base -base;

has [qw(app config)];

sub name {'first_second'}

sub process {
    my ( $self, $job, %args ) = @_;

    $args{cb}->( $self->config );
}

1;

