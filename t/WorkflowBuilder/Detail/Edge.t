use strict;
use warnings FATAL => 'all';

use Test::Exception;
use Test::More;


use_ok('Ptero::WorkflowBuilder::Detail::Edge');

{
    my $edge = Ptero::WorkflowBuilder::Detail::Edge->new(
        source => 'source node', source_property => 'output',
        destination => 'destination node', destination_property => 'input'
    );

    my $expected_hashref = {
        source => 'source node',
        destination => 'destination node',
        sourceProperty => 'output',
        destinationProperty => 'input',
    };
    is_deeply($edge->to_hashref, $expected_hashref, 'typical edge produces expected hashref');
};

{
    my $expected_hashref = {
        source => 'source node',
        destination => 'destination node',
        sourceProperty => 'output',
        destinationProperty => 'input',
    };
    my $edge = Ptero::WorkflowBuilder::Detail::Edge->from_hashref($expected_hashref);
    is_deeply($edge->to_hashref, $expected_hashref, 'edge roundtrip from/to_hashref');
};

{
    my $edge = Ptero::WorkflowBuilder::Detail::Edge->new(
        source_property => 'output',
        destination => 'destination node', destination_property => 'input'
    );

    my $expected_hashref = {
        source => 'input connector',
        destination => 'destination node',
        sourceProperty => 'output',
        destinationProperty => 'input',
    };
    is_deeply($edge->to_hashref, $expected_hashref, 'missing source node uses input connector');
};

{
    my $edge = Ptero::WorkflowBuilder::Detail::Edge->new(
        source => 'source node', source_property => 'output',
        destination_property => 'input'
    );

    my $expected_hashref = {
        source => 'source node',
        destination => 'output connector',
        sourceProperty => 'output',
        destinationProperty => 'input',
    };
    is_deeply($edge->to_hashref, $expected_hashref,
        'missing destination node uses output connector');
};

{
    my $edge = Ptero::WorkflowBuilder::Detail::Edge->new(
        source => 'single-node', source_property => 'output',
        destination => 'single-node', destination_property => 'input',
    );

    is_deeply([$edge->validation_errors],
        ['Source and destination nodes on edge are both named "single-node"'],
        'source and destination nodes on edge have same name');
};

{
    use Ptero::WorkflowBuilder::Task;

    my $source_name = 'coerce-source-task';
    my $destination_name = 'coerce-destination-task';

    my $source = Ptero::WorkflowBuilder::Task->new(
        name => $source_name,
    );
    my $destination = Ptero::WorkflowBuilder::Task->new(
        name => $destination_name,
    );

    my $edge = Ptero::WorkflowBuilder::Detail::Edge->new(
        source => $source, source_property => 'output',
        destination => $destination, destination_property => 'input',
    );

    my $expected = {
        source => $source_name, sourceProperty => 'output',
        destination => $destination_name, destinationProperty => 'input',
    };

    is_deeply($edge->to_hashref, $expected, 'test');
}

done_testing();
