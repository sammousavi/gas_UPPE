function [Keldysh_parameter,W,relative_ne,g] = calc_photoionization_parameter(prop_output,fiber,sim,gas_material)
%CALC_PHOTOIONIZATION_PARAMETER This code computes some parameters used
%in the Perelomov-Popov-Terent'ev (PPT) photoionization model or generated
%from it.
%   
% Input:
%
%   prop_output.fields: (Nt,?,?); the electric field under the time domain
%   prop_output.dt: scalar (ps)
%   fiber.SR:  scalar; 1/Aeff=SR value (Aeff: mode-field area) (1/m^2)
%   sim.f0: scalar; center frequency (THz)
%   gas_material: a string; the gas material such as 'H2', 'N2', etc.
%
% Output:
%   Keldysh_parameter: (Nt,?,?)
%   W: (Nt,?,?); ionization rate (Hz)
%   relative_ne: (Nt,?,?); the relative free electron number density (ne/Ng), Ng: total gas number density
%   g: (Nt,?,?); one parameter in the exponent in W, used to check g/|A| to
%                see the actual ionization strength relation 
%                since W is proportional to exp(-C*g/|A(t)|), 
%                C: some constant, |A|: electric field (from prop_output.fields)

%% Ionization potential
switch gas_material
    case 'H2'
        ionization_energy = 15.43; % eV
    case 'N2'
        ionization_energy = 14.5341; % eV
    case 'Ar'
        ionization_energy = 15.76; % eV
    case 'He'
        ionization_energy = 24.5874; % eV
    case 'Kr'
        ionization_energy = 14.00; % eV
    case 'Xe'
        ionization_energy = 12.13; % eV
    case 'Ne'
        ionization_energy = 20.18; % eV
    otherwise
        error('This code doesn''t support the ionization computation of other materials yet');
end
e = 1.60217663e-19; % Coulomb
ionization_energy = ionization_energy*e; % J

%% Keldysh parameter
me = 9.1093837e-31; % kg
permittivity0 = 8.85418782e-12; % m^(-3)/kg*s^4*A^2
c = 299792458; % m/s

Nt = size(prop_output.fields,1);

instantaneous_omega = zeros(size(prop_output.fields));
for zi = 1:numel(prop_output.fields)/Nt
    pulse_phase = unwrap(angle(prop_output.fields(:,zi)));
    pulse_phase = conv(pulse_phase,ones(floor(Nt/100),1)/floor(Nt/100),'same'); % smoothing is required; otherwise, it's too noisy such that an erroneous high-frequency number is calculated
    omega_pulse = -(pulse_phase(3:end)-pulse_phase(1:end-2))/(2*prop_output.dt)+2*pi*sim.f0; % THz; I use "central difference" to calculate the slope here
    omega_pulse = [omega_pulse(1);omega_pulse;omega_pulse(end)]*1e12; % Hz
    omega_pulse(abs(prop_output.fields(:,zi))<max(abs(prop_output.fields(:,zi)))/100) = min(omega_pulse);
    
    instantaneous_omega(:,zi) = omega_pulse;
end

inverse_Aeff = fiber.SR;
I = abs(prop_output.fields).^2*inverse_Aeff; % intensity; W/m^2

% This modification is for I too small to avoid spurious result in 1./I computation
for zi = 1:numel(prop_output.fields)/Nt
    I_zi = I(:,zi);
    I_zi(I_zi<max(I_zi)/1e5) = max(I_zi)/1e5;
    
    I(:,zi) = I_zi;
end

ponderomotive_energy = e^2/2/me/permittivity0/c*I./instantaneous_omega.^2;
Keldysh_parameter = sqrt(ionization_energy/2./ponderomotive_energy);

%% Photoionization - erfi() lookup table
% Because calculating erfi is slow, it's faster if I create a lookup table
% and use interp1. The range of input variable for erfi is 0~sqrt(2) only.
n_Am = 10; % the number of summation of Am term in photoionization
erfi_x = linspace(0,sqrt(2*(n_Am+1)),1000)';
erfi_y = erfi(erfi_x);

%%
k = 4*pi*permittivity0;
h = 6.62607015e-34; % m^2*kg/s
hbar = h/2/pi;
a0 = k*hbar^2/me/e^2; % Bohr radius
U_H = e^2/k/a0/2; % hydrogen ionization energy = 13.6 eV

n = sqrt(U_H/ionization_energy); % effective principal quantum number

kappa = 4*ionization_energy*sqrt(2*me*ionization_energy)/hbar/e;

v = ionization_energy/hbar./omega_pulse.*(1+1/2./Keldysh_parameter.^2);
n_v = ceil(v)-v + (0:10); % the minimum positive number of n-v+S, where S, an integer, adds n-v until it becomes a positive number

beta = 2*Keldysh_parameter./sqrt(1+Keldysh_parameter.^2);
g = 3/2./Keldysh_parameter.*((1+1/2./Keldysh_parameter.^2).*asinh(Keldysh_parameter) - sqrt(1+Keldysh_parameter.^2)/2./Keldysh_parameter);

% the PPT correction factor
A0 = sum(2/sqrt(3)*Keldysh_parameter.^2./(1+Keldysh_parameter.^2).*exp(-2*n_v.*asinh(Keldysh_parameter)).*interp1(erfi_x,erfi_y,sqrt(beta.*n_v)),2);
A0(Keldysh_parameter<0.8) = 1;

W = 2^(2*n)/n/gamma(n)/gamma(n+1)*ionization_energy/hbar*sqrt(6/pi)*A0.*(sqrt(permittivity0*c/2./I)*kappa./sqrt(1+Keldysh_parameter.^2)).^(2*n-1.5).*exp(-sqrt(permittivity0*c/2./I)*kappa/3.*g);
W(I<max(I)/1e4) = 0;

% Number density of the gas
relative_ne = cumsum(W)*(prop_output.dt*1e-12);
% Below is the more accurate version with integrating factor.
% It's important only when relative_ne approaches the gas number density.
%integrating_factor = exp(cumsum(W)*(prop_output.dt*1e-12));
%relative_ne = cumsum(W.*integrating_factor)*(prop_output.dt*1e-12)./integrating_factor;

end