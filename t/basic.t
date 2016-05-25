use Mojo::Base -strict;

use lib 't/lib';

use Test::More;
use Test::Exception;
use Devel::Cycle qw(find_cycle);

subtest '_find_modules' => sub {
    use Mojolicious::Plugin::Minion::Tasks;

    my @modules
        = Mojolicious::Plugin::Minion::Tasks::_find_modules('MyApp::Task');

    is_deeply(
        \@modules,
        [
            map {"MyApp::Task::$_"} (
                'Failed',         'One',
                'One::NoProcess', 'One::Two',
                'Two::One',       'Two::Two::AlreadyRegistered',
            )
        ],
        'Modules found'
    );
};

throws_ok(
    sub {

        package MyApp::MinionFirst {
            use Mojolicious::Lite;

            plugin 'Minion::Tasks' => {};
        }
    },
    qr/seems Minion plugin is not loaded/,
    'Plugin::Minion needed first'
);

throws_ok(
    sub {

        package MyApp::NoNamespace {
            use Mojolicious::Lite;

            plugin 'Minion' => { Test => {} };
            plugin 'Minion::Tasks' => {};
        }
    },
    qr/namespace not provided/,
    'required namespace'
);

subtest 'errors: no config, loading failed' => sub {
    no warnings 'redefine';
    local *Mojo::Log::error = sub {
        my $error = $_[1];

        if ( $error =~ /::Failed/ ) {
            like(
                $error,
                qr/loading '[^']+?' failed:/,
                'loading failed error message'
            );
        }
        else {
            like(
                $error,
                qr/no config provided for 'MyApp::Task::/,
                'config error message'
            );
        }
    };

    package MyApp::NoConfig {
        use Mojolicious::Lite;

        local $SIG{__WARN__} = sub { };

        plugin 'Minion'        => { Test      => {} };
        plugin 'Minion::Tasks' => { namespace => 'MyApp::Task', };
    };
};

subtest 'register' => sub {
    no warnings 'redefine';
    local *Mojo::Log::error = sub {
        my $error = $_[1];

        if ( $error =~ /::NoProcess/ ) {
            like(
                $error,
                qr/has no 'process' method/,
                'no "process" method error message'
            );
        }
        elsif ( $error =~ /::AlreadyRegistered/ ) {
            like(
                $error,
                qr/ already registered/,
                'task name already registered',
            );
        }
    };

    package MyApp::SingleNS {
        use Mojolicious::Lite;

        local $SIG{__WARN__} = sub { };

        plugin 'Minion' => { Test => {} };
        plugin 'Minion::Tasks' => {
            namespace     => 'MyApp::Task',
            task_defaults => { default => 'config' },
            'One::Two'    => {
                one => { two => 'config' },
            },
        };
    };

    package MyApp::MultiNS {
        use Mojolicious::Lite;

        local $SIG{__WARN__} = sub { };

        plugin 'Minion' => { Test => {} };
        plugin 'Minion::Tasks' => {
            namespace => [ 'MyApp::Task::One', 'MyApp::Task::Two' ],
            task_defaults => { default => 'config' },
            Two           => {
                'MyApp::Task::One' => {
                    one => { two => 'config' },
                },
                'MyApp::Task::Two' => {
                    two => { two => 'config' },
                }
            }
        };

    };

    for my $info (
        { app => MyApp::SingleNS->app, name => 'Single namespace' },
        { app => MyApp::MultiNS->app,  name => 'Multiple namespaces' },
        )
    {
        subtest $info->{name} => sub {
            my $app    = $info->{app};
            my $worker = $app->minion->worker->register;

            my $cfg;

            $app->minion->enqueue(
                first_second => [ cb => sub { $cfg = shift } ] );
            _start_job($worker);
            is_deeply( $cfg, { one => { two => 'config' } },
                'config provided' );

            $app->minion->enqueue( two => [ cb => sub { $cfg = shift } ] );
            _start_job($worker);
            is_deeply( $cfg, { default => 'config' }, 'default config' );

            my $has_cycles = 0;
            find_cycle( $app, sub { $has_cycles = 1 } );
            ok( !$has_cycles, 'No cycles' );
        };
    }
};

done_testing();

# Start job in current process
sub _start_job {
    my ($worker) = @_;

    my $job  = $worker->dequeue(0);
    my $task = $job->task;
    my $cb   = $job->minion->tasks->{$task};
    $job->fail($@) unless eval { $job->$cb( @{ $job->args } ); 1 };
}
