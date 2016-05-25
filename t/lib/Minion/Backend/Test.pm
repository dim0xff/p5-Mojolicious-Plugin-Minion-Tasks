package Minion::Backend::Test;

use Mojo::Base 'Minion::Backend';

has '_jobs';

sub repair { }

sub enqueue {
    my ( $self, $task ) = ( shift, shift );
    my $args    = shift // [];
    my $options = shift // {};

    my $job = {
        args  => $args,
        id    => rand,
        state => 'inactive',
        task  => $task
    };

    $self->_jobs( {} ) unless $self->_jobs;
    $self->_jobs->{ $job->{id} } = $job;

    return $job->{id};
}

sub register_worker {
    my ( $self, $id ) = @_;

    return $id // rand;
}

sub dequeue {
    my ( $self, $id, $wait, $options ) = @_;

    my $tasks = $self->minion->tasks;

    my @jobs =                                  #
        grep { $tasks->{ $_->{task} } }         #
        grep { $_->{state} eq 'inactive' }      #
        values %{ $self->_jobs };               #

    return undef unless my $job = $jobs[0];

    @$job{qw(started state worker)} = ( time, 'active', $id );

    return $job;
}

1;
