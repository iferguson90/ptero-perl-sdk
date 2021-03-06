package Ptero::WorkflowBuilder::DAG;

use Moose;
use warnings FATAL => 'all';

use Data::Dump qw();
use JSON qw();
use List::MoreUtils qw();
use Params::Validate qw(validate_pos :types);
use Set::Scalar qw();
use Graph::Directed qw();

use Ptero::WorkflowBuilder::Detail::Edge;
use Ptero::WorkflowBuilder::Task;

with 'Ptero::WorkflowBuilder::Detail::HasValidationErrors';
with 'Ptero::WorkflowBuilder::Detail::Node';

my $codec = JSON->new()->canonical([1]);

has nodes => (
    is => 'rw',
    isa => 'ArrayRef[Ptero::WorkflowBuilder::Detail::Node]',
    default => sub { [] },
);

has edges => (
    is => 'rw',
    isa => 'ArrayRef[Ptero::WorkflowBuilder::Detail::Edge]',
    default => sub { [] },
);


sub add_node {
    my ($self, $node) = @_;
    push @{$self->nodes}, $node;
    return $node;
}

sub add_edge {
    my ($self, $edge) = @_;
    push @{$self->edges}, $edge;
    return $edge;
}

sub create_edge {
    my $self = shift;
    my $edge = Ptero::WorkflowBuilder::Detail::Edge->new(@_);
    $self->add_edge($edge);
    return $edge;
}

sub connect_input {
    my $self = shift;
    my %args = Params::Validate::validate(@_, {
            source_property => { type => SCALAR },
            destination => { type => SCALAR|OBJECT },
            destination_property => { type => SCALAR },
    });

    $self->create_edge(%args);
    return;
}

sub connect_output {
    my $self = shift;
    my %args = Params::Validate::validate(@_, {
            source => { type => SCALAR|OBJECT },
            source_property => { type => SCALAR },
            destination_property => { type => SCALAR },
    });

    $self->create_edge(%args);
    return;
}

sub node_named {
    my ($self, $name) = @_;

    for my $node (@{$self->nodes}) {
        if ($node->name eq $name) {
            return $node
        }
    }

    return;
}

sub node_names {
    my $self = shift;

    my $node_names = Set::Scalar->new('input connector', 'output connector');
    for my $node (@{$self->nodes}) {
        $node_names->insert($node->name);
    }
    return $node_names;
}

sub sorted_edges {
    my $self = shift;

    return [sort { $a->sort_key cmp $b->sort_key } @{$self->edges}];
}

sub _property_names_from_edges {
    my ($self, $query_name, $property_holder) = @_;

    my $property_names = new Set::Scalar;

    for my $edge (@{$self->edges}) {
        if ($edge->$query_name) {
            $property_names->insert($edge->$property_holder);
        }
    }
    return $property_names->members;
}

around 'input_properties' => sub {
    my $orig = shift;
    my $self = shift;
    my $properties = Set::Scalar->new($self->$orig());
    $properties->insert($self->_property_names_from_edges('external_input',
            'source_property'));
    return sort $properties->members();
};

sub output_properties {
    my $self = shift;
    return sort $self->_property_names_from_edges('external_output',
        'destination_property');
}

sub from_hashref {
    my ($class, $hashref, $name) = validate_pos(@_, 1,
        {type => HASHREF}, {type => SCALAR});

    my %params = (
        name => $name,
    );
    if (exists $hashref->{parallelBy}) {
        $params{parallel_by} = $hashref->{parallelBy};
    }
    my $self = $class->new(%params);

    for my $edge_hashref (@{$hashref->{edges}}) {
        $self->add_edge(Ptero::WorkflowBuilder::Detail::Edge->from_hashref($edge_hashref));
    }

    while (my ($node_name, $node_hashref) = each %{$hashref->{nodes}}) {
        if (exists $node_hashref->{nodes}) {
            $self->add_node(Ptero::WorkflowBuilder::DAG->from_hashref(
                    $node_hashref, $node_name));
        } elsif (exists $node_hashref->{methods}) {
            $self->add_node(Ptero::WorkflowBuilder::Task->from_hashref(
                    $node_hashref, $node_name));
        } else {
            die sprintf(
                'Could not determine the class to instantiate with hashref (%s)',
                Data::Dump::pp($node_hashref)
            );
        }
    }

    return $self;
}

sub to_hashref {
    my $self = shift;

    my @edges = map {$_->to_hashref} sort {$a->sort_key cmp $b->sort_key} @{$self->edges};
    my %nodes = map {$_->name, $_->to_hashref} @{$self->nodes};

    my $result = {
        edges => \@edges,
        nodes => \%nodes,
    };
    if ($self->has_parallel_by) {
        $result->{parallelBy} = $self->parallel_by;
    }
    return $result;
}

sub from_json {
    my ($class, $json_string, $name) = validate_pos(@_, 1,
        {type => SCALAR}, {type => SCALAR});
    my $hashref = $codec->decode($json_string);

    return $class->from_hashref($hashref, $name);
}

sub to_json {
    my $self = shift;
    my %p = Params::Validate::validate(@_, {
        pretty => {default => 0},
    });

    $self->validate;
    if ($p{pretty}) {
        return $codec->pretty->encode($self->to_hashref);
    } else {
        return $codec->encode($self->to_hashref);
    }
}

##############################
# Validations
##############################

sub _node_name_errors {
    my $self = shift;
    my @errors;

    my $node_names = new Set::Scalar;
    my @duplicates;
    for my $node (@{$self->nodes}) {
        if ($node_names->contains($node->name)) {
            push @duplicates, $node->name;
        }
        $node_names->insert($node->name);
    }

    if (@duplicates) {
        push @errors, sprintf(
            'Duplicate node names: %s',
            Data::Dump::pp(sort @duplicates)
        );
    }

    return @errors;
}

sub edge_sources {
    my $self = shift;

    my $edge_sources = new Set::Scalar;
    for my $edge (@{$self->edges}) {
        $edge_sources->insert($edge->source);
    }
    return $edge_sources;
}

sub edge_destinations {
    my $self = shift;

    my $edge_destinations = new Set::Scalar;
    for my $edge (@{$self->edges}) {
        $edge_destinations->insert($edge->destination);
    }
    return $edge_destinations;
}

sub _edge_target_errors {
    my $self = shift;
    my @errors;

    my $invalid_edge_targets =
        ($self->edge_sources + $self->edge_destinations) - $self->node_names;

    unless ($invalid_edge_targets->is_empty) {
        push @errors, sprintf(
            'Edges have invalid targets: %s',
            Data::Dump::pp(sort $invalid_edge_targets->members)
        );
    }

    return @errors;
}

sub _orphaned_node_errors {
    my $self = shift;
    my @errors;

    my $orphaned_node_names =
        $self->node_names - $self->edge_destinations - 'input connector';

    unless ($orphaned_node_names->is_empty) {
        push @errors, sprintf(
            'Orphaned node names: %s',
            Data::Dump::pp(sort $orphaned_node_names->members)
        );
    }

    return @errors;
}

sub _encode_target {
    my ($self, $node_name, $prop_name) = @_;
    return Data::Dump::pp($node_name, $prop_name);
}

sub _get_mandatory_inputs {
    my $self = shift;

    my $result = new Set::Scalar;

    for my $node (@{$self->nodes}) {
        for my $prop_name ($node->input_properties) {
            $result->insert($self->_encode_target($node->name, $prop_name));
        }
    }

    return $result;
}

sub _node_input_errors {
    my $self = shift;
    my @errors;

    my $mandatory_inputs = $self->_get_mandatory_inputs;
    for my $edge (@{$self->edges}) {
        my $destination = $self->_encode_target(
            $edge->destination, $edge->destination_property);
        if ($mandatory_inputs->contains($destination)) {
            $mandatory_inputs->delete($destination);
        }
    }

    unless ($mandatory_inputs->is_empty) {
        push @errors, sprintf(
            'No edges targeting mandatory input(s): %s',
            # $mandatory_inputs->members are already pp'd, so we can just join
            (join ', ', sort $mandatory_inputs->members)
        );
    }

    return @errors;
}

sub _dag_output_errors {
    my $self = shift;
    my @errors;

    for my $edge (@{$self->edges}) {
        my $node = $self->node_named($edge->source);

        next unless defined $node;

        unless ($node->is_output_property($edge->source_property)) {
            push @errors, sprintf(
                'Node %s has no output named %s',
                Data::Dump::pp($edge->source),
                Data::Dump::pp($edge->source_property)
            );
        }
    }

    return @errors;
}

sub _multiple_edge_target_errors {
    my $self = shift;
    my @errors;

    my %destinations;

    for my $edge (@{$self->edges}) {
        my $destination = $edge->destination_to_string;
        push @{$destinations{$destination}}, $edge;
    }

    for my $destination (keys %destinations) {
        my @edges = @{$destinations{$destination}};

        if (@edges > 1) {
            push @errors, sprintf(
                'Destination %s is targeted by multiple edges from: %s',
                Data::Dump::pp($destination),
                Data::Dump::pp(sort map { $_->source_to_string } @edges)
            );
        }
    }

    return @errors;
}

sub _cycle_errors {
    my $self = shift;
    my @errors;

    my $g = Graph::Directed->new();
    for my $edge (@{$self->edges}) {
        $g->add_edge($edge->source, $edge->destination);
    }

    for my $region ($g->strongly_connected_components) {
        if (@$region > 1) {
            push @errors, sprintf("A cycle exists involving the following nodes: %s",
                Data::Dump::pp(sort @$region));
        }
    }
    return @errors;
}

sub validation_errors {
    my $self = shift;

    my @errors = map { $self->$_ } qw(
        _name_errors
        _node_name_errors
        _edge_target_errors
        _orphaned_node_errors
        _node_input_errors
        _dag_output_errors
        _multiple_edge_target_errors
        _cycle_errors
    );

    # Cascade validations
    for (@{$self->nodes}, @{$self->edges}) {
        push @errors, $_->validation_errors;
    }

    return @errors;
}

sub validate {
    my $self = shift;
    my @errors = $self->validation_errors;
    if (@errors) {
        die sprintf(
            "DAG named %s failed validation:\n%s",
            $self->name, (join "\n", sort @errors)
        );
    }
    return;
}


__PACKAGE__->meta->make_immutable;
