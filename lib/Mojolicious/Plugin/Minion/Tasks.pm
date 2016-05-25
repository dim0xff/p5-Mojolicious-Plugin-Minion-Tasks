package Mojolicious::Plugin::Minion::Tasks;

# ABSTRACT: Auto-register Minion tasks from modules by provided namespace

use Mojo::Base 'Mojolicious::Plugin';

use Scalar::Util qw(weaken);
use File::Basename qw(fileparse);
use File::Spec::Functions qw(catdir catfile splitdir);
use Mojo::Loader qw(load_class);

sub register {
    my ( $self, $app, $args ) = @_;

    $args //= {};

    # Minion should be initialized first
    my $minion = eval { $app->minion }
        or die __PACKAGE__, ": seems Minion plugin is not loaded\n";

    my $namespace = $args->{namespace}
        or die __PACKAGE__, ": namespace not provided\n";

    $namespace = [$namespace] unless ref $namespace eq 'ARRAY';

    $app->log->info("Initializing Minion::Tasks plugin");

    _register_ns( $app, $minion, $args, $_ ) for ( @{$namespace} );
}

sub _register_ns {
    my ( $app, $minion, $args, $ns ) = @_;

MODULE:
    for my $module ( _find_modules($ns) ) {
        if ( my $error = load_class($module) ) {
            $error =~ s/\s*$//;                 # remove exception \n
            _error( $app, "loading '$module' failed: $error" );
            next MODULE;
        }

        my $task_name = $module =~ s/^$ns :://rx;

        # Try to get config
        if (
            my $cfg = (
                  exists $args->{$task_name}
                ? $args->{$task_name}{$ns}
                        ? $args->{$task_name}{$ns}
                        : $args->{$task_name}
                : $args->{task_defaults}
            )
            )
        {
            my $task = $module->new( config => $cfg, app => $app );

            if ( !$task->can('process') ) {
                _error( $app, "'$module' has no 'process' method" );
                next MODULE;
            }

            $task_name
                = $task->can('name')
                ? $task->name
                : lc( $task_name =~ s/::/_/gr );

            if ( exists $minion->tasks->{$task_name} ) {
                _error( $app,
                    "'$module': task '$task_name' already registered" );
                next MODULE;
            }

            # Register task in minion
            weaken( $task->{app} );
            $minion->add_task( $task_name => sub { $task->process(@_) } );

            $app->log->debug( __PACKAGE__
                    . ": '$module' loaded with '$task_name' task name" );
        }
        else {
            _error( $app, "no config provided for '${ns}::$task_name'" );
        }
    }

    $minion->repair;
}

# Errors helper
sub _error {
    my ( $app, $error ) = @_;

    $error = __PACKAGE__ . ": $error";
    $app->log->error($error);
    warn "$error\n";
}

# Recursive search
sub _find_modules {
    my $ns = shift;

    my %modules;
    for my $directory (@INC) {
        next unless -d ( my $path = catdir $directory, split( /::|'/, $ns ) );

        opendir( my $dir, $path );
        for my $file ( grep { !/^\.\.?$/ } readdir $dir ) {
            if ( -d catfile splitdir($path), $file ) {
                $modules{$_}++ for _find_modules("${ns}::$file");
            }
            elsif ( $file =~ /\.pm$/ ) {
                $modules{ "${ns}::" . fileparse $file, qr/\.pm/ }++;
            }
        }
    }

    return sort keys %modules;
}

1;

__END__

=head1 SYNOPSIS

    # In your app.pl
    use Mojolicious::Lite;

    plugin 'Minion'        => {...};
    plugin 'Minion::Tasks' => {
        namespace         => 'MyApp::Task',
        task_defaults     => {},
        'Upload::Picture' => {
            quality => 95,
            resize  => '2048x2048'
        },
    };

    post '/upload/image' => sub {
        my $c = shift;

        my $upload = $c->req->upload('file');
        $upload->move_to('/tmp/temp.file');

        $c->minion->enqueue(
            upload_picture => [ filename => '/tmp/temp.file' ]
        );

        $self->render( json => { status => 'queued' } );
    };



    # In MyApp/Task/Upload/Picture.pm
    package MyApp::Task::Upload::Picture;
    use Mojo::Base -base;

    has [qw(app config)];

    sub name {'first_second'}

    sub process {
        my ( $self, $job, %args ) = @_;

        my $filename = $args{filename};

        # do something with file
    }

    1;

=head1 DESCRIPTION

Allow you to define and auto register Minion tasks from your task modules.

All tasks needs configuration which could be provided via L<default config|/task_defaults>
or per-task config.

Per-task configuration provided via HASH:

    Task::Module => {
        key => value,
        ...
    }

If Task::Module presents in several namespaces, it is possible to provide
config per namespace:

    namespace => ['MyApp::Task', 'OtherApp::Task', 'AnotherOne']
    'File::Upload' => {
        'MyApp::Task'    => { ... },
        'OtherApp::Task' => { ... },

        default_key => default_value,
        ...
    }
    # Here AnotherOne::File::Upload will get next config:
    # {
    #   'MyApp::Task'    => { ... },
    #   'OtherApp::Task' => { ... },
    #
    #   default_key => default_value,
    #   ...
    # }

All task modules have to have:

=over 1

=item accessor C<app>

Here will be link to application instance.

=item accessor C<config>

Module config will be placed here.

=item method C<process>

It will be called on job performing.

=back

All tasks will be registered with their own names. Task name could be provided
via C<name> method in module (which should return task name). If there are no
method C<name> in module, then task name will be get automatically based
on module name:

    namespace - MyApp::Task

    MyApp::Task::Upload::Picture -> upload_picture
    MyApp::Task::Delete          -> delete


=attr namespace

Where to search modules to load. Looking in C<@INC> for modules.

Could be string or array of namespaces.


=attr task_defaults

Default task configuration.
